---
title: "Responsive Images With Nginx on Ubuntu"
description: "Here's how to configure Nginx to create responsive images for you on demand."
author: "Monica Lent"
tags: ["nginx", "responsive web design"]
date: 2019-01-06T10:22:42+01:00
---

I started looking into this topic because, as you've probably heard, Google
changed its pagespeed insights tool (and search ranking algorithm) to **focus on
mobile-first**. I've got an image-heavy blog that does pretty well in Google,
but my pagespeed score was somewhere between 75 and 80. One of Google's
biggest complaints to me were that **my images were not resized properly**.

The only problem is I have **hundreds of images** on that blog, and there was
no way on earth I was going to actually create mobile-friendly versions of
every single image.

Nginx to the rescue! Nginx has a neat module called image_filter which
will do the work for you and **resize images on the fly**. This is awesome
because it means you also only resize the images people are requesting
instead of all the images.

Here's how to achieve responsive images with Nginx.

## Install the Nginx image_filter module

So, there are a number of different tutorials on how to achieve this, but
apparently none of them considered sharing exactly how you can install
this module.

If you simply run:

```bash
sudo apt-get install nginx-module-image-filter
```

There's a good chance the server is going to tell you that it cannot find
this illustrious image filter module! Annoyingly,
[the official Nginx documentation](https://www.nginx.com/blog/responsive-images-without-headaches-nginx-plus/) only explains how to achieve this using Nginx Plus, which is
apparently an enterprise version of Nginx. But there are also
[other blog posts](https://stumbles.id.au/nginx-dynamic-image-resizing-with-caching.html)
on this topic, and surely not everyone is using Nginx Plus.

Eventually, I found [a website](https://ubuntu.pkgs.org/16.04/nginx-amd64/nginx-module-image-filter_1.14.1-1~xenial_amd64.deb.html) which explained how to enable this module
by enabling additional sources in Ubuntu. The instructions are copied here:

1. Add the following line to `/etc/apt/sources.list` (the following of course depends on the Ubuntu version you are running):<br/>
   `deb http://nginx.org/packages/ubuntu/ xenial nginx`
2. Install GPG key of the repository:<br/>
   `wget https://nginx.org/keys/nginx_signing.key && sudo apt-key add nginx_signing.key`
3. Update the package index:<br/>
   `sudo apt-get update`
4.  Install nginx-module-image-filter deb package:<br/>
    `sudo apt-get install nginx-module-image-filter`

## Enable the Nginx image_filter module

Open up `/etc/nginx/nginx.conf` and in the outermost scope (not inside `events` or `http`
or anything like that), load the module:

```nginx
load_module modules/ngx_http_image_filter_module.so;
```

> _Note: "ngx" is not a typo. That's what it's called._

Check that your configuration seems good at this point with:

```bash
nginx -t
```

If it all looks good, you'll get:

```bash
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

On to the next step!

## Add a new location in your Nginx server configurations

So, the first step is simply to create a rule in one of your enabled sites
that some path is going to grab and resize images. The most basic
setup looks like this:

```nginx
server {
    # Whatever stuff you already have in your server block
    server_name mywebsite.com;

    # The new section you can copy/paste in
    location ~ "^/media/(?<width>\d+)/(?<image>.+)$" {
        alias /opt/mywebsite/public/images/$image;
        image_filter resize $width -;
        image_filter_jpeg_quality 75;
        image_filter_buffer 8M;
    }
}
```

Obviously you should change `/opt/mywebsite/public/images/$image` to be the path
to the images you already have. The important thing for later is that you
keep the path in parallel to however you access images today.

For example, if today you load images via:

```
www.mywebsite.com/images/file.jpg
```

You want to make sure that your responsive route is something like:

```
www.mywebsite.com/media/320/images/file.jpg
```

Rather than:

```
www.mywebsite.com/media/320/file.jpg
```

In which case, in the previous example, you should route to
`/opt/mywebsite/public` instead. At least, that's what you want if,
like me, you're running a statically generated site and you want to
modify the underlying shortcode you're using for images without needing
to do string manipulation on your paths.

## Add a server cache

So, both the official Nginx docs and the other blog post (which I guess is
derived from the Nginx docs) suggest that instead of just resizing the pictures
on demand, you create a second server that acts as a cache. Makes sense.
Here's how that looks:

```nginx
# Internal image resizing server.
server {
  server_name localhost;
  listen 8888;

  location ~ "^/media/(?<width>\d+)/(?<image>.+)$" {
    alias /opt/mywebsite/public/$image;
    image_filter resize $width -;
    image_filter_jpeg_quality 80;
    image_filter_buffer 8M;
  }
}

# Your other server
server {
  listen 443 ssl;

  # Whatever other rules your server has are here
  # Like certs, other locations, etc.

  # Pass requests to your resizing server
  location ~ "^/media/(?<width>(640|320))/(?<image>.+)$" {
    proxy_pass http://localhost:8888/media/$width/$image;
    proxy_cache images;
    proxy_cache_valid 200 24h;
  }

  # I got this from one of the tutorials, apparently it helps avoid the error
  # "no resolver defined to resolve localhost"
  location /media {
    proxy_pass http://localhost:8888/;
  }
}
```

Here I've specified two widths, 640px and 320px for our images. You can obviously
add new ones, change these to whatever you want, etc.

Run `nginx -t` and then `service nginx restart` to reload the configuration.

Open up an image you have on your server to check that it's working as
expected! For instance:

```
www.mywebsite.com/media/640/path/to/image.jpg
```

It should be resized to the proper width!

## Use the responsive images

Ok, so now we need to take those images and use them! There are lot of different
ways to do responsive images apparently, but I don't really care about them.
Here is the dead-simplest way to just get the images to load a different
resolution on smaller devices:

```html
<img
  src="/path/to/image.jpg"
  srcset="/path/to/image.jpg 1024w, /media/640/path/to/image.jpg 640w, /media/320/path/to/image.jpg 320w"
/>
```

In my case, I'm using Hugo as a static site generator, so the code looks a bit
more like this:

```go
{{ $src := .Params.image }}
<img
  src="{{ $src }}"
  srcset="{{ $src }} 1024w, /media/640{{ $src }} 640w, /media/320{{ $src }} 320w"
/>
```

Apply this to whatever way you are using the images currently.

## Implications for testing locally

So, the blog I'm running this on is using a "outdated" set of tools, like
jQuery and Gulp. But I have no interest in updating them, as it works perfectly
fine. I also don't have proper deployments, it's just running on a Digital
Ocean droplet somewhere, and when I run the blog locally, I'm using
Hugo's development server, not Nginx.

So the question is: **How can I get this not to break my local development
experience?**

If I wanted to over-engineer it I would probably put it in Docker, but instead
I just hacked around it in the shortcode template:

```go

  {{ if eq (printf "%v" $.Site.BaseURL) "http://localhost:1313/" }}
    srcset="{{ $src }} 1024w, {{ $src }}?w=640 640w, {{ $src }}?w=320 320w"
  {{ else }}
    srcset="{{ $src }} 1024w, /media/640{{ $src }} 640w, /media/320{{ $src }} 320w"
  {{ end }}
```

Obviously this code is not super robust but...it's a blog. So far so good ;)

## Results

I did a few things to improve image loading on the blog to appease Google:

1. Made all the images in the body of blog posts responsive
2. Used the resized versions in all previews of posts (like the list page or recommended posts at the bottom of an article)
3. Lazy loaded all images below the fold

These things put together **brought the pagespeed score on my blog's homepage
to 92**! Google still hates that some of its own scripts (looking at you Google
Maps) aren't cached long enough, but I'm finally "in the green" with Google.

I can't speak for how this would scale, to give you an idea, my blog gets
about 30k pageviews per month / 1-1.3k per day, so it's not massive, but it
is very image-heavy.

A quick check on the size of my cache, which lives for 24h:

```bash
du -sh /tmp/nginx-images-cache/
> 21M     /tmp/nginx-images-cache/
```

And that's for about 350 images (at least, I'm assuming that each of these
cache items is in fact an image, who knows what Nginx is doing inside):

```bash
find /tmp/nginx-images-cache/ -type f | wc -l
> 352
```

I should also mention that I have Cloudflare as a CDN in front of my website,
which caches roughly 50% of the requests that would come to my server.

---

**I hope this helps you add responsive images to your website using Nginx!**
If you have any questions, feel free to reach out on twitter
[@monicalent](http://twitter.com/monicalent).
