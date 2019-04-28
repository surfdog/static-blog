---
title: "Independent Deployment for the Frontend with Docker and Kubernetes"
description: "So you want to deploy part of your monolithic frontend app independently? Learn how."
date: 2019-03-15T11:36:30+01:00
---

I recently gave a talk entitled, "Independent deployment for the Frontend
with Docker and Kubernetes". As it turns out, the topic of wanting to deploy
independently resonated with quite a lot of people. I received emails and
tweets with quite a few specific questions, and wanted to take the time to
explain how the demo is working in more detail.

{{% callout %}}

Before diving in, I want to be clear that you shouldn't take this post at
face value as advice for your personal situation. Here I'm presenting a few
different means to make it possible to deploy part of your frontend separately.
My examples use React, though I'm rather sure you can achieve this using
other libraries or frameworks.

{{% /callout %}}

- Purpose and goals
- Main challenges
  - Loading components remotely
  - Serving components from a microservice
  - Deployment
- What's missing?
- Resources

## Purpose and goals

The goal of the demo, and this post, is to show one way you can achieve
independent deployment for the frontend, especially if you're working in
an environment where Docker and Kubernetes have become the standard tools.

The demo itself **is not meant to be production-ready**, but instead to
be a simple as possible (fewest dependencies, fewest files, etc.) so that
the underlying concept can get across:

> You can load your UI components from a remote server, embed them in
> your single page app, and run a dev-friendly version on your local machine
> and push the same code with minor tweaks to a remote server.

How you adapt these concepts and technologies is your use case is up to you
:smile:

Let's get started!

## Main challenges

I think it's helpful to go over some of the main challenges we have to solve
when wanting to deploy a piece of our frontend separately.

The most obvious issue from the frontend perspective is this: How can I get my
component, which webpack is not aware of at build-time, so I can use it
somewhere? If I simply `fetch` a JavaScript file, **all I get back is a bunch of
text** and no clear way to turn that text into something that spits out a module
I can treat as a React component.

Read on to learn how we can load a separately built module in
an async manner, and then use the component in that module inside React.

{{% callout %}}

**Remotely loaded components vs. code splitting**

I should be clear here, what we are trying to accomplish is not the same
as code-splitting or simply lazy-loading (for which you might use a
library like `react-loadable`). Libraries like webpack have a runtime
and a manifest they use to handle all interactions between modules
in your app while it's running in the browser. Our challenge is that the code
we want to load is not known to webpack at build time.

[Read more about webpack's manifest and runtime](https://webpack.js.org/concepts/manifest/)

{{% /callout %}}

### Loading components remotely

Let's start by looking at the kind of API we want to achieve for our
remote-loading component, and then try to fill in the gaps.

```javascript
// We create a component that will fetch its own source
// code remotely, anywhere we use <MyFragment/>

const MyFragment = asyncComponent({
  /* Some options here */
});

// ...
return (
  <Switch>
    <Route exact path="/" component={props => (
        <MyFragment {...props} />
      )}
    />
  </Switch>
);
```

That's pretty neat, but how does `asyncComponent` work? We can start
with a skeleton implementation like this:

```javascript
import React, { Component } from 'react';

export default function asyncComponent({ /* some options here */ }) {
  class AsyncComponent extends Component {
    static Component = null;
    state = { Component: AsyncComponent.Component };

    componentWillMount() {
      if (!this.state.Component) {
        // Something magical happens here so that
        // somehow, we can do this.setState({ Component: MyFragment })
        // But what?
      }
    }
    render() {
      const { Component } = this.state;

      if (Component) {
        return <Component {...this.props} />;
      }

      return null;
    }
  }
  return AsyncComponent;
}
```

Somehow, we need to accomplish three things:

1. Figure out where to get our Javascript from
2. Load that Javascript into the browser
3. Extract the Component we want and use it

For #1 this is actually solved pretty easily using the
[webpack-assets-plugin](https://www.npmjs.com/package/assets-webpack-plugin),
you can generate a `manifest.json` file after every build that looks something
like this:

```json
{
  "bundle": {
    "js": "/node.bc7a306156ccd0089f59.bundle.js"
  },
  "metadata": {
    "componentName": "MyFragment"
  }
}
```

Meaning that we can start to fill in some blanks for our `asyncComponent`
function like this.

```javascript
const MyFragment = asyncComponent({
  prefix: '/fragments/node', // Route our microservice is exposed, explained later
  loadManifest: () =>
    fetch('/fragments/node/manifest.json').then(resp => resp.json())
});
```

```javascript
    componentWillMount() {
      if (!this.state.Component) {
        loadManifest().then(manifest => {
          const {
            bundle: { js },
            metadata: { componentName }
          } = manifest;

          // Now what?

        });
      }
    }

```

Now, let's focus on problems #2 and #3: Loading JavaScript into the browser and
extracting the Component we want, and using it so we can fill out our function.

It seems simple but as we'll see, it's not totally straightforward. Let's
have a look at a couple of different approaches. You may find that one
approach works better for you.

1. **Native browser modules**<br/>
  <u>Pros:</u> Native. Future-proof. Sharing dependencies (if you want to do that)
  looks pretty straightforward with [import maps](https://github.com/WICG/import-maps) and
  [webpack externals](https://webpack.js.org/configuration/externals/).<br/>
  <u>Cons:</u> Native module transpilation target is not yet supported by Webpack.
  Not supported in all browsers. [Shims exist](https://github.com/guybedford/es-module-shims).
  You still need to bundle your code (not shown here) in order to
  transpile like JSX.<br/><br/>

3. **SystemJS** -- <br/>
  <u>Pros:</u> Acts as a fallback for native ES modules. Small footprint.
  <br/>
  <u>Cons:</u> Not officially supported by webpack (you need to switch to Rollup).
  <br/><br/>

2. **Eval and babel in the browser** -- <br/>
  <u>Pros:</u> Doesn't require exposing anything to window. You can continue
  to use webpack. Works in any browser.
  <br/>
  <u>Cons:</u> You ship a transpiler with your app code (heavy). Use of `eval`.
  <br/><br/>

4. **Script tags and window** -- <br/>
  <u>Pros:</u> Can be added to your existing toolchain. 
  <br/>
  <u>Cons:</u> Usage of `window`.
  <br/><br/>

For the sake of simplicity, my demo uses approach #4. While the usage of
`window` isn't desirable, I find it an acceptable trade off for a few reasons.
One, the control of the name of the global variable remains with the microservice
exposing it. So you never need to deploy the host application to change the
name of the fragment component. Two, you can define fitness functions and
an abstract pipline during CI to ensure that the fragments are properly
formatted.

You may have different requirements and find another approach to have better
tradeoffs. Feel free to select the approach that works for you, or share
another approach.

### Serving components from a microservice

Now that we are transpiling and bundling our components, as well as producing
a manifest file that will tell consumers of the component how to access it,
we want to bring up a web server in our Kubernetes cluster.

{{% callout %}}

This post cannot cover how to set up Docker, Kubernetes, and Helm on your
local machine. Instead, check out a number of great resources on this topic:

- [Installation instructions for Helm and Tiller](https://docs.helm.sh/using_helm/#installing-helm)

{{% /callout %}}

#### Web server

Our web server in this case is a simple Node app. You might wonder -- why
should be bother with a Node server as opposed to chucking the files on
a CDN? Why not just use Nginx?

In the real world you'd probably want to do that. However, you may
also want that each of our independently deployable components can have
its own **backend-for-frontend**. There are pros and cons to sharing
these vs. giving each component its own.

Here's our sample Node server's code, which is simply responsible for
serving our static JSON manifest.

```javascript
const express = require('express');
const morgan = require('morgan');

const app = express();
const port = process.env.PORT || 3001;
const host = '0.0.0.0';

app.use(express.static('dist'));
app.use(morgan('combined'));
app.listen(port, host);

console.log(`Example app listning on ${port}!`);

```

Now that we have our Node app, it's time to put it in a container.

#### Docker

There's nothing too exciting about the Dockerfile. In this example I'm using
Alpine, though you'd likely opt for a different Linux distribution.

```docker
FROM node:8.1.4-alpine
RUN apk update
RUN apk add yarn

WORKDIR /usr/src/app

COPY package.json .
COPY yarn.lock .

RUN yarn 

COPY . .

RUN yarn build

EXPOSE 3001

CMD ["yarn", "start"]

```

From the root directory of the project, you can run the following command to
build and tag a Docker container on your local machine:

```bash
docker build -f .deployment/docker/Dockerfile . -t fragment-node:v1
```

Once you've done this, you should be able to go to localhost:3001/manifest.json
to see that your app's manifest is exposed (that is, after you've successfully
built the frontend with `yarn build`).

#### Kubernetes

Now that we are running this one part of our independently deployable component,
we can start to define some Kubernetes resources for them. If you have zero
knowledge about Kubernetes, I would encourage you to watch some YouTube videos
that will boil down the core concepts for you.

{{% callout %}}

**Why not just docker-compose?**

Docker compose is a popular option for bringing up multiple containers in
tandem. There are a couple of caveats if you want to use docker compose.
The first one is that all your fragments are defined in a single file. The
second being that in theory, you need to bring up all the components together
(which, on a local machine, is not very scalable owing to RAM constraints).
By using Kubernetes, it's easier to bring up new versions of our containers
without needing to touch other services.

{{% /callout %}}

#### Setting up resources for the Nginx Ingress

An Ingress is a type of Kubernetes resources that helps us route traffic from
the outside internet into services that are running inside our Kubernetes
cluster. Perhaps the most popular variation is the Nginx ingress,
which you can install on your local machine in the following way:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/mandatory.yaml

# If using minikube
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/mandatory.yaml

# If using Docker for Mac
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/provider/cloud-generic.yaml

# Check that it's working properly
kubectl get pods --all-namespaces -l app=ingress-nginx
```

Those yaml files are exactly the same as the ones we're about to define for our
own services, just a bit longer. Once we get to our production cluster,
we'll need to do this again, as well as configure our service account in GKE
to provision the types of resources we need. That'll be covered in the
Deployment section below.

#### Creating the Helm charts

Once we have our Docker image in our local registry, we can make it run inside
its own service inside our k8s cluster. To do that, we can either hardcode
our YAML configurations, or we can use Helm.

While Helm is much more powerful than we see in the following example, we can
use Helm as a template engine to interpolate either dev or production values
into our kubernetes manifests.

To do so, you typically separate your `values.yaml` files from files that
are named `00-resource-type.yml`. The numbers at the front help you to ensure
that your resources are applied in the right order.

**values.yaml** -- This file defines our default values which we'll interpolate
to all the different templates.

```yaml
Replicas: 1
ExpectedClusterSize: 1
RevisionHistoryLimit: 3

Image:
  repository: localhost
  name: fragment-node
  tag: v1
  pullPolicy: Always

name: fragment-node
namespace: default

service:
  type: ClusterIP
  port: 3001

```

**service.yaml** -- Defines the service we want to run in the cluster. Its
port should match the one exposed by Node inside our container.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.name }}
  namespace: {{ .Values.namespace }}
  labels:
    name: {{ .Values.name }}
    namespace: {{ .Values.namespace }}
spec:
  selector:
    name: {{ .Values.name }}
    namespace: {{ .Values.namespace }}
  ports:
  - port: {{ .Values.service.port }}
    targetPort: http
    protocol: TCP
    name: http
  type: {{ .Values.service.type }}

```

**deployment.yaml** -- Defines which Docker container to bring up, how many
replicas, the port, and if we're running in dev, it'll also allow us to
mount a local directory into the container for local development.

```yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: {{ .Values.name }}
  namespace: {{ .Values.namespace }}
  labels:
    name: {{ .Values.name }}
    namespace: {{ .Values.namespace }}
spec:
  replicas: {{ .Values.Replicas }}
  selector:
    matchLabels:
      name: {{ .Values.name }}
      namespace: {{ .Values.namespace }}
  template:
    metadata:
      labels:
        name: {{ .Values.name }}
        namespace: {{ .Values.namespace }}
    spec:
      containers:
      - name: {{ .Values.name }}
        image: "{{ .Values.Image.name }}:{{ .Values.Image.tag }}"
        imagePullPolicy: {{ .Values.Image.pullPolicy }}
        env:
          - name: PORT
            value: {{ .Values.service.port | quote }}
        ports:
          - name: http
            containerPort: {{ .Values.service.port }}
            protocol: TCP
      {{ if .Values.isDev }}
        volumeMounts:
          - mountPath: {{ .Values.volume.mountPath }}
            name: {{ .Values.volume.name }}
            readOnly: false
      volumes:
        - name: {{ .Values.volume.name }}
          hostPath:
            path: {{ .Values.volume.path }}
      {{ end }}
```

**ingress.yaml** -- Directs requests to a certain path to the service that
is selected in the file.

```yml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: {{ .Values.name }}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - http:
      paths:
        - path: /fragments/node
          backend:
            serviceName: {{ .Values.name }}
            servicePort: {{ .Values.service.port }}
```

We also have a separate `dev.yaml` file which contains development values.

At this point, we would be able to run either the production or the local
configurations on our machine. To use the default `values.yaml` file,
you can run this command:

```
helm install --name fragment-node .deployment/chart
```

To run the development version, you can run this command.

```
helm install -f .deployment/chart/dev.yml --name fragment-node .deployment/chart
```

Be sure to open up and edit `.deployment/chart/dev.yml` and provide
the path to your own `dist` folder for `volume.path`.

If you need to reload after you've added new values to a file, you can do
so using this command:

```
helm upgrade -f .deployment/chart/dev.yml fragment-home .deployment/chart
```

To verify that it works, you would need to open http://localhost/api/fragments/node/manifest.json.
Building the docker files and applying the helm charts is something you'd need
to do for both the host app and the fragment app. When more fragments are present,
it's also possible to recursively apply helm charts from a root directory.

### Deployment

Once we see the app running on our local machine, we want to run it in
a cluster somewhere in the cloud. The easiest option is to use GKE (Google
Kubernetes Engine), which allows you to bring up a k8s cluster by clicking
a button.

#### Using the Google Kubernetes Engine

The main tricky bit when setting up your cluster for deployment by
CI is getting the permissions of the service account right. A service account
is an account you'll use to run commands inside the cluster to build new
images and apply changes to the production cluster. The permissions required
to allocate an Nginx ingress cannot be assigned via the GUI and instead
must be applied via the command line.

#### Deploying with CircleCI

Once our "production" cluster is configured in GKE, we can set up
CircleCI. You can read through the configuration to see what it does,
but I will just quickly point out a couple of things worth mentioning:

* Technically Helm has a server-side component called Tiller (which will
  be deprecated). Here we're basically using Helm as a glorified templating
  engine so no need for that fancy stuff.
* You need to generate credentials and upload them to CircleCI for your
  deployment account.
* Technically it's "not cool" to generate helm charts to stdout and then
  pipe the config to your cluster, as it means the cluster is not
  reproducible. A common practice is to generate the charts, upload
  them to a storage system (such as Amazon S3) and then apply them. For
  simplicity's sake, I have not added this extra step in the sample code.

For a full tutorial about how to deploy to a k8s cluster in GKE using
CircleCI, check out [this blog post](http://www.url.com) which
explained everything I needed to get it working, _except_ what I mentioned
above about adjusting the permissions of the existing service account.

```yaml
version: 2
jobs:
  build:
    docker:
      - image: circleci/node:10
    working_directory: ~/repo
    steps:
      - checkout
      - restore_cache:
          keys:
            - v1-dependencies-{{ checksum "package.json" }}
            - v1-dependencies-
      - run:
          name: Install dependencies
          command: yarn install
      - save_cache:
          paths:
            - node_modules
          key: v1-dependencies-{{ checksum "package.json" }}
      - run:
          name: Run build
          command: yarn build
  deploy_k8s:
    docker:
      - image: google/cloud-sdk
    environment:
      - PROJECT_NAME: "fragment-node"
      - GOOGLE_PROJECT_ID: "our-service-138623"
      - GOOGLE_COMPUTE_ZONE: "europe-west1-b"
      - GOOGLE_CLUSTER_NAME: "microfrontends"
    steps:
      - checkout
      - run:
          name: Install Helm
          command: |
            curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash
            helm init -c
      - run:
          name: Setup Google Cloud SDK
          command: |
            echo $GCLOUD_SERVICE_KEY > ${HOME}/gcloud-service-key.json
            gcloud auth activate-service-account --key-file=${HOME}/gcloud-service-key.json
            gcloud --quiet config set project ${GOOGLE_PROJECT_ID}
            gcloud --quiet config set compute/zone ${GOOGLE_COMPUTE_ZONE}
            gcloud --quiet container clusters get-credentials ${GOOGLE_CLUSTER_NAME}
      - setup_remote_docker
      - run:
          name: Docker build and push
          command: |
            docker build \
              --build-arg COMMIT_REF=${CIRCLE_SHA1} \
              --build-arg BUILD_DATE=`date -u +"%Y-%m-%dT%H:%M:%SZ"` \
              -f ./.deployment/docker/Dockerfile \
              -t ${PROJECT_NAME} .
            docker tag ${PROJECT_NAME} eu.gcr.io/${GOOGLE_PROJECT_ID}/${PROJECT_NAME}:${CIRCLE_SHA1}
            gcloud auth print-access-token | docker login -u oauth2accesstoken --password-stdin https://eu.gcr.io
            docker push eu.gcr.io/${GOOGLE_PROJECT_ID}/${PROJECT_NAME}:${CIRCLE_SHA1}
      - run:
          name: Deploy to Kubernetes
          command: |
            helm template \
              --name="${PROJECT_NAME}" \
              --set Image.name="eu.gcr.io/${GOOGLE_PROJECT_ID}/${PROJECT_NAME}" \
              --set Image.tag="${CIRCLE_SHA1}" \
              ./.deployment/chart \
              | kubectl apply -f -
            kubectl rollout status deployment/${PROJECT_NAME}
workflows:
  version: 2
  ultimate_pipeline:
    jobs:
      - build
      - deploy_k8s:
          requires:
            - build
          filters:
            branches:
              only: master

```

With these files and the configured cluster, you should be able to make changes
to your cluster, push to master branch, and see them reflected on
your "production" cluster. You can access them using the IP address assigned
to your Nginx ingress resource.

## What's missing?

- Deduplicating shared dependencies
- Caching / sharing of API data
- Sharing UI through a design system

## References

Most of this concept is gluing together tons of different concepts and
tutorials.  Here are a few of the resources that I found most useful when
creating this proof of concept.

* [Tips for developing locally with Docker for Mac and Kubernetes](https://github.com/jnewland/local-dev-with-docker-for-mac-kubernetes)
* [Introduction to Kubernetes Ingresses](https://medium.com/@cashisclay/kubernetes-ingress-82aa960f658e)
* [Example of a basic nginx ingress](https://matthewpalmer.net/kubernetes-app-developer/articles/kubernetes-ingress-guide-nginx-example.html)
* [Custom nginx ingress controller on GCE](https://zihao.me/post/cheap-out-google-container-engine-load-balancer/)
* [Introduction to Helm](https://www.digitalocean.com/community/tutorials/an-introduction-to-helm-the-package-manager-for-kubernetes)
* [Telepresence: Local development against a remote Kubernetes cluster](https://github.com/telepresenceio/telepresence)
