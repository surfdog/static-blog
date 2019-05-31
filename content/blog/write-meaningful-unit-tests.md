---
title: "How to write meaningful unit tests in React apps"
date: 2019-05-31T21:11:09+02:00
type: "posts"
---

I don't care what anyone says, unit tests are the bedrock of shipping code with
confidence. 

## What should a good unit test give you?

## Writing good unit tests

### Make it deterministic

**Strategy: Use pure functions.**

### Avoid mocking

**Strategy: Inject third-party dependencies as function arguments.**

### Use the language of your domain

**Strategy: Write tests from the standpoint of the user.**

Sometimes that user is your end user, sometimes it's another developer. It's
important to understand which situation you are in.

### Test your logic and view layer separately

**Strategy: Extract logic to separate modules.**

## Signs your unit test ain't so good

## Tips for writing testable code

- Use pure functions
- Separate logic from the view layer
- Inject third-party dependencies as function arguments
- Extract your API layer

## Checklist for a good unit test

- Deterministic
- Free of mocking
