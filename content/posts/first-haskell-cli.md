+++
title = "Create your first Haskell CLI"
description = "A gentle introduction to Haskell by building a simple CLI."
author = "Monica Lent"
tags = ["haskell", "stack"]
date = "2018-08-11T11:06:04+02:00"

+++

Even though I'm mostly writing Javascript for my day job, I like to experiment
with other neat technologies in my free time. Two of the tools I find most
interesting these days is Haskell and Docker. So I set out to develop my first
ever CLI in Haskell, while running the tool inside a container.

Follow this tutorial if you have ever been curious about Haskell but wanted to
take a gentle introduction to getting started. I'm only a Haskell hobbyist, so
do feel free to recommend improvements or more "canonical" ways of doing things
via twitter [@monicalent](http://twitter.com/monicalent).

Enjoy the article!

## Install haskell and related tools

### Create a dockerfile

In this tutorial we're going to be running our Haskell code inside Docker.
If you prefer to develop on your host machine, you can check out
the guides on the Haskell website for [macOS](https://www.haskell.org/platform/mac.html)
and other platforms. 

For the rest of you, create a new directory for your project
(mine is called `haskell-cli` and is located at `/opt/haskell-cli`).

Dockerfile:

```dockerfile
# Start out from a debian machine
FROM debian:stretch-slim

# Install a few necessary packages
RUN apt-get update
RUN apt-get install --yes haskell-platform haskell-stack cabal-install

# Check that it worked
CMD ["cabal", "--version"]
```

> **Note:** There are existing Dockerfiles that will come with all these tools
> pre-installed for you, such as `haskell:8.0.2`. However, since it's a tutorial
> let's take the time to understand what's being installed and how :)

> **Another note:** Originally I wanted to use nix rather than stack as my
> package manager, but there are issues running it in docker on an OS that's
> not nixOS.  You can watch the [open issue on github](https://github.com/NixOS/nix/issues/971).

Build the dockerfile and give it a tag for easy reference.

```bash
docker build . --tag=my-haskell
```

Run your container and execute `gchi` in it. This command stands for
Glasgow Haskell Compiler (with the "i" likely standing for "interactive").

Now you can do your very first math in Haskell!

```bash
❯ docker run -it my-haskell ghci
GHCi, version 8.0.2: http://www.haskell.org/ghc/  :? for help
Prelude> 1 + 2
3
Prelude>
Leaving GHCi.
```

You can escape ghci using <kbd>cmd</kbd> + <kbd>d</kbd>.

That wasn't so difficult was it? We just created a Dockerfile that has
Haskell ands its relevant tools installed, and did a little bit of math.
Let's move on to creating our first file.

## Create your first file

Open up a file called `Main.hs` and type:

```haskell
module Main where

main :: IO()
main = putStr "Hello world"
```

Now build this file and execute it with Docker. Let's look at the necessary
commands and then walk through what they are doing step by step.

```bash
❯ docker run -v $PWD:/src -w /src -it my-haskell ghc --make Main.hs
[1 of 1] Compiling Main             ( Main.hs, Main.o )
Linking Main ...

/opt/haskell-cli
❯ ls
Dockerfile  Main  Main.hi  Main.hs  Main.o

/opt/haskell-cli
❯ docker run -v $PWD:/src -w /src -it my-haskell ./Main
Hello world
```

1. `docker run -v $PWD:/src -w /src -it my-haskell ghc --make Main.hs`
   First we tell Docker to mount our current working directory inside
   the container using `-v` (standing for "volume"). This basically means we
   can work on our host machine and our files will be accessible inside docker.
   Then we use `-w` to indicate the working directory, where the container
   should start working from after start up. Finally, we build our
   Haskell code using `gch --make Main.hs` which results in a `Main`
   executable on our host machine.
2. `ls` In the host machine, you can see all the files that are generated
   by the Haskell compiler: `Main`, `Main.hi`, and `Main.o`.
3. Finally, you can execute the `Main` file inside the container by running
   `docker run -v $PWD:/src -w /src -it my-haskell ./Main`.
