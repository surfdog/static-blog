---
title: "Independent Deployment for the Frontend with Docker and Kubernetes"
description: "So you want to deploy part of your monolithic frontend app independently? Learn how."
date: 2019-03-15T11:36:30+01:00
---

I recently gave a talk at **JS Kongress** entitled, "Independent deployment
for the Frontend with Docker and Kubernetes". As it turns out, the topic of
wanting to deploy independently resonated with quite a lot of people. I received
emails and tweets with quite a few specific questions, and wanted to take the
time to explain how the demo is working in more detail.

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
somewhere? If I simply `fetch` a JavaScript file, all I get back is a bunch of
text and no clear way to turn that text into something that spits out a module
I can treat as a React component.

Read on to learn how we can load a separately built module in
an async manner, and then use the component in that module inside React.

{{% callout %}}

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

1. **Native browser modules** --
3. **SystemJS** --
2. **Eval and babel in the browser** --
4. **Script tags and window** --

#### Approach #1: Native browser modules

Let's assume that the module we want to load today is available to our
app at `/fragments/node/node.bc7a306156ccd0089f59.bundle.js` and our
component is named `MyFragment` (which we know because we fetched the
manifest JSON file).

Perhaps one of the cleanest ways to get the content of this component
is for that component to exist as a native ECMAscript module.

For instance:

```
import React from 'react';

export default function MyFragment() {
  return <div>Hello World</div>
}
```

> _Not mentioned here, but in order to import from 'react' you'll need something
> called an import map. I'll leave you to google it_

And then import that dynamically with something like:

```javascript
    componentWillMount() {
      if (!this.state.Component) {
        loadManifest().then(manifest => {
          const {
            bundle: { js },
            metadata: { componentName }
          } = manifest;

          const src = `${prefix}${js}`
          import(src).then(module => {
            const Component = module.exports.default;
            AsyncComponent.Component = Component;
            this.setState({ Component });
          });
        });
      }
    }
```

**Pros** -- Native. Future-proof. Sharing dependencies (if you want to do that)
looks pretty straightforward with [import maps](https://github.com/WICG/import-maps) + [webpack externals](https://webpack.js.org/configuration/externals/).

**Cons** -- Not supported in all browsers. [Shims exist](https://github.com/guybedford/es-module-shims).
You still need to bundle your code (not shown here) in order to transpile like
JSX.

### Serving components from a microservice

#### Docker

#### Kubernetes

#### Helm

### Deployment

#### Using the Google Kubernetes Engine

#### Deploying with CircleCI

## What's missing?

- Deduplicating shared dependencies
- Caching / sharing of API data
- Sharing UI through a design system
