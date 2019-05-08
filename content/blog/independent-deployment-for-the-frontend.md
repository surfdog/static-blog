---
title: "[DRAFT] Independent Deployment for the Frontend with Docker and Kubernetes"
description: "So you want to deploy part of your monolithic frontend app independently? Learn how."
type: "posts"
date: 2019-03-15T11:36:30+01:00
---

I recently gave a talk entitled, "Independent deployment for the Frontend
with Docker and Kubernetes". As it turns out, the topic of wanting to deploy
independently resonated with quite a lot of people. I received emails and
tweets with a number of few specific questions, and wanted to take the time to
explain how the demo is working in more detail.

{{% callout %}}

Before diving in, I want to be clear that you shouldn't take this post at
face value as advice for your personal situation. Here I'm presenting a few
different means to make it possible to deploy part of your frontend separately.
My examples use React, though I'm rather sure you can achieve this using
other libraries or frameworks.

{{% /callout %}}

- [Purpose and goals](#purpose-and-goals)
- [Main challenges](#main-challenges)
  - [Loading components remotely](#load-components-remotely)
  - [Serving components from a microservice](#serve-components-from-a-microservice)
  - [Deployment](#deployment)
- [What's missing?](#whats-missing)
  - [Deduplicating shared dependencies](#deduplicating-shared-dependencies)
  - [Data and caching](#data-and-caching)
  - [Visual consistency](#visual-consistency)
  - [How to share code](#how-to-share-code)
  - [End-to-end testing](#end-to-end-testing)
  - [What about being framework agnostic?](#framework-agnostic)
- [Final words](#final-words)
- [Resources](#resources)

## Purpose and goals {#purpose-and-goals}

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

## Main challenges {#main-challenges}

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

### Loading components remotely {#load-components-remotely}

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

For #1 this is actually solved for us by the
[webpack-assets-plugin](https://www.npmjs.com/package/assets-webpack-plugin),
which can generate a `manifest.json` file after every build that looks something
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
  <u>Cons:</u> Native module transpilation target is [not yet supported by Webpack](https://github.com/webpack/webpack/issues/2933)
  though there seems to be a [plugin](https://www.npmjs.com/package/webpack-babel-multi-target-plugin)
  that can do it.  Not supported in all browsers. [Shims exist](https://github.com/guybedford/es-module-shims).
  You still need to bundle your code (not shown here) in order to
  transpile, e.g. JSX.<br/><br/>

3. **SystemJS**<br/>
  <u>Pros:</u> Acts as a fallback for native ES modules. Small footprint. [Can
  finally be used with webpack](https://github.com/systemjs/systemjs#compatibility-with-webpack)
  as of April 12, 2019. Can alternatively be used with Rollup.
  <br/>
  <u>Cons:</u> If used with webpack, duplication of webpack runtime code.
  <br/><br/>

2. **Eval and babel in the browser** ([Code sample](https://codepen.io/qborreda/pen/JZyEaj), not mine)<br/>
  <u>Pros:</u> Doesn't require exposing anything to window. You can continue
  to use webpack. Works in any browser.
  <br/>
  <u>Cons:</u> You ship a transpiler with your app code. Use of `eval`. If used with
  webpack, duplication of webpack runtime code.
  <br/><br/>

4. **Script tags and window** <br/>
  <u>Pros:</u> Can likely be added to your existing toolchain without major modifications.
  <br/>
  <u>Cons:</u> Usage of `window` (potential clashes). If used with webpack,
  duplication of webpack runtime code.
  <br/><br/>

For the sake of simplicity, my demo uses approach #4. While the usage of
`window` isn't desirable, I find it an acceptable trade off for a few reasons.
One, the control of the name of the global variable remains with the microservice
exposing it. So you never need to deploy the host application to change the
name of the fragment component. Two, you can define fitness functions and
an abstract pipline during CI to ensure that the fragments are properly
formatted.

I also think that #4 keeps the tooling to a minimum and lets us focus more
on the mechanics and deployment, which is the goal of the demo.

That said, if I were to write the demo again I would first try approach #2
now that webpack supports SystemJS as a target.

You may have different requirements and find another approach to have better
tradeoffs. Feel free to select the approach that works for you, or share
another approach. Hopefully this gives you a good starting point for
your exploration!

### Serving components from a microservice {#serve-components-from-a-microservice}

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

> **NOTE** -- These are a lot of long commands for a developer to learn
> and memorize. Going forward, I would abstract out a lot of the repetition
> into a shared CLI.

### Deployment {#deployment}

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

## What's missing? {#whats-missing}

Beyond the technical implementation of loading a component remotely,
embedding it, and deploying it independently, there are a number of
considerations to take into account. While many of these points could be
their own posts, I'll share a few words about them briefly to give you
a starting point in case you want to go further.

### Deduplicating shared dependencies

Depending on your situation, you may want to share e.g. one "copy" of
React across all the different pages in your app. One reason for this is
that sometimes, different versions of the same library can lead to conflicts.
Another reason is simply bundle size and performance.

Naturally, the trade off is a degree of dependency between your independently
deployable subcomponents -- if you want to upgrade that library, there is a
risk of regression in each subcomponent. And if you have a large number of
teams, each with their own subcomponents, you run the risk of needing to
coordinate a lot of regression testing during library upgrades (unless, of
course, you have a robust and comprehensive set of tests covering the full test
pyramid -- realistically most people I speak with are not in this
luxurious position).

As I shared earlier, if you decide that sharing some of these larger libraries
is the right approach for your app, take a look into the following two
options:

- [Webpack externals](https://webpack.js.org/configuration/externals/)
- [ES modules and import maps](https://github.com/WICG/import-maps)

Depending on your application specifics, one or the other might be more
appropriate.

### Data and caching

What do you do in a client application when the same data is needed in many
places? Or you want to avoid the client needing to re-download the same data
when it visits different pages? This is tricky because anything you share
can quickly become a dependency that causes side effects. This is also a key
reason that microservices should have their own data sources (e.g. own
database) rather than a shared database across all services.

One of the most common approaches for sharing data in the microservices world
is through an event bus. But how can you avoid getting into a giant mess
of brittle events, like we had with code littered with `$rootScope.$broadcast`
back in the day?

Consider a mixed approach, where frequently changing data that must not be
stale (think: the current user object) is exposed to all subpages via an API
layer that provides an observable to subcomponents consuming information.
This core information is always available and up to date.

The rest of the data can be stored in a separate API layer per page (or per
subcomponent, depending on what level of granularity your situation requires),
provided in a standard format via a version library (ideally also with
static types). This ensures consistency, promotes good practices between
the different subpages, yet ensures that only the data most critical to the
user experience is shared between pages, eliminating most data-related
side effects.

> **NOTE** -- This is another place where having each microservice per
> sub-component can come in handy, because developers have the option to combine
> requests server-side. This comes with the drawback that different subpages
> are working with differently structured data from an API, and it can be
> confusing to cross-reference API documentation with custom request-combining code.
> I do not have production experience with GraphQL, which may be an interesting
> solution to this problem, as long as we do not ignore the potential side
> effects of relying on shared data and sufficiently test end-to-end experiences.

### Visual consistency

If you let everyone do their best to implement designs to spec, you will
invariably have a UI and UX that wildly diverges as you move throughout
your application. The core solution to this problem is a design system:
a component library, implemented in code, combined with standards, governance,
and processes for introducing changes. It is versioned and released like
any other product. You can't get away with sharing CSS and expecting it to
work out. As I've described in my talk about [building design systems that scale]({{< ref "speaking.md#tech-behind-a-design-system-that-scales" >}}),
CSS is the wrong level of abstraction for building UI components because
it does not sufficiently encapsulate function, behavior, and design.

### How to share code in general {#how-to-share-code}

This brings me to a larger point -- sharing code in general. Whether you're
deploying code independently or not, sharing code in a large app can become
tricky as often times "reusable" code becomes brittle and side-effect
ridden if not thoughtfully considered. I would encourage you to share code
via libraries which are separately versioned and released. You can hear
more of my thoughts on how to share code in larger apps in my talk about
[building resilient frontend architecture]({{< ref "speaking.md#building-resilient-frontend-architecture" >}}).

Do as much as you can to automate and ease updating these libraries for the
teams, so it's more or less effortless for them to keep up-to-date.

### End-to-end testing

Despite the fact that you may deploy independently, your end-to-end tests
need to run on the composed application and should include user stories
that cross technical and team boundaries. This is a massive topic, but
don't forget about it when setting up the CI aspect of your independently
deployable subcomponents.

### What about being "framework agnostic"? {#framework-agnostic}

One of the big draws (and the big turn-offs, for many) of microfrontends
is the potential of being "framework agnostic". As with everything, there 
are tradeoffs -- Are you really going to implement your design system
in multiple frameworks? Is that the best way to spend your resources?
Are there real merits for choosing to add a new framework over the existing
one when comparing our modern options, e.g. React, Vue, Angular? Or is it
that it's easier not to try to form a consensus? And finally -- is the
extra page weight, loading time for our users, learning curve, custom setups,
and variance of best practices worth it?

Naturally, in an independently deployed subcomponent, you can glue together
just about anything with JavaScript. The question is what the balance of
tradeoffs is in a specific app, and if a company honestly has the resources
to maintain a multi-framework setup (or, a micro-frontend setup for that matter).

Microfrontends can enable more team autonomy, but there is a fine line between
autonomy and anarchy. Core constraints and architectural patterns must be
standardized and enforced in a way that is as automated as possible.

## Final words

Distributed frontend apps is not a solved problem. We are all striving for a
good balance between user experience, developer experience, and scalability.
There are many approaches, and many people do it differently. In this space, we
are severely missing best practices and shared learnings (both from successes
and failures).  Most talks about microfrontends, including mine, can only
scratch the surface of all the complexity and setup required to get it done.
Working demos are great, but we need more large-scale application studies as the
frontend becomes more featureful and more complex. If you're working in an
environment like this, whether you're happy with your setup or struggling to
make it fit together, please share your story so we can learn from each other!

## References

Most of this concept is gluing together tons of different concepts and
tutorials. Here are a few of the resources that I found most useful when
creating this proof of concept.

### Docker, Kubernetes, and Helm

* [Tips for developing locally with Docker for Mac and Kubernetes](https://github.com/jnewland/local-dev-with-docker-for-mac-kubernetes)
* [Introduction to Kubernetes Ingresses](https://medium.com/@cashisclay/kubernetes-ingress-82aa960f658e)
* [Example of a basic nginx ingress](https://matthewpalmer.net/kubernetes-app-developer/articles/kubernetes-ingress-guide-nginx-example.html)
* [Custom nginx ingress controller on GCE](https://zihao.me/post/cheap-out-google-container-engine-load-balancer/)
* [Introduction to Helm](https://www.digitalocean.com/community/tutorials/an-introduction-to-helm-the-package-manager-for-kubernetes)
* [Telepresence: Local development against a remote Kubernetes cluster](https://github.com/telepresenceio/telepresence)

### Talks and blog posts on microfrontends

{{% callout %}}

**Want to work on interesting problems like this?**

We are hiring engineers to work on our microfrontends solution, among
other challenging projects like our shared libraries, tooling, design
system, and developer productivity for the web. If that sounds like
something you'd enjoy, check out these two listings:

* [Senior Frontend Engineer](#)
* [Web Architect](#)

Feel free to reach out on twitter or by email if you feel like a strong
match for either of these roles.

{{% /callout %}}
