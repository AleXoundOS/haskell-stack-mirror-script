### This script downloads everything you need to develop software in Haskell
(except remote documentation)

That is: **stack infrastracture** and **hackage packages**.

In order to establish the **offline mirror** you need a *http server* to serve
downloaded files.

### Usage
Run [mirror.sh]
(https://github.com/AleXoundOS/haskell-dev-mirror-script/blob/master/mirror.sh)
with the following options or none accepting defaults.

Options (by argument number):

1. Custom mirror directory (default: "mirror" in current path).
2. Custom address of http server (default: "http://localhost:3000").

After successful run it provides:
* mirror directory that is ready to be served by a http server (like nginx,
apache, mighttpd2, lighttpd, etc)
* generated "config.yaml" needed to be placed on clients here:
"~/.stack/config.yaml"

The script also performs:
* checking downloaded files integrity
* skipping of downloaded checked files on consequent runs

### Requirements
* bash + core-utils (tee, cut, test, sort, comm, printf, etc...)
* grep
* sed
* git
* wget
* tar
* gzip
* sha1sum

### Issues
* Currently *stack* does not correcly support `setup-info:` field in
"config.yaml". Related issue: [#1]
(https://github.com/AleXoundOS/haskell-dev-mirror-script/issues/1).
This means that in order to run `stack setup`
you have to supply a path to "mirror/stack-setup-mirror.yaml" manually with
`--setup-info-yaml` option. So if running on server side it can be:
```
stack setup --setup-info-yaml /srv/http/haskell-dev-mirror/stack-setup-mirror.yaml
```

* Bash script can be error-prone with it's imperative nature and intended to be
as a temporary solution until a good Haskell program will be developed.

* *stack* setup yaml is parsed in a pretty tricky way as well as request fields
in urls. Mirror directory does not retain original url path structure. So in
theory collisions may happen.

* Only Unix-like systems are supported directly. Running bash script in other
environments may require special treatment. Sorry I don't have a suitable
working non-Unix system and not so confident to adjust script to them without
testing.

* The list of required programs to be installed prior to running the script
is not short. Though these are all pretty standard on any Unix-like OS.

* As of 2017-03-04 there is one broken package on Hackage: hermes-1.3.4.3, that
has missing files on the server, thus causing some warning messages to show.
It's ok.

### Tested configuration
Tested on Arch Linux x86_64 (2017-03-03) with nginx.
<details><summary>nginx configuration example (/etc/nginx/nginx.conf) assuming
that you put mirror directory into "/srv/http/haskell-dev-mirror"</summary>
```nginx
events {
    worker_connections  1024;
}
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    server {
        listen       3000;
        server_name  haskell-dev-mirror;
        location / {
            root /srv/http/haskell-dev-mirror;
        }
    }
}
```
</details>

As of 2017-03-04 a fully downloaded mirror directory uses 20&nbsp;GiB of space.
Approximate time it takes to verify all files integrity ~15&nbsp;minutes on a
2.2Ghz&nbsp;CPU. In case there are no new files it takes less than a minute to
check for updates.

### TODO
Investigate the possibility of an uncomplicated way to mirror remote Hackage
documentation (and maybe other).

### Inspiration and thanks
This project is inspired by
[offline-stack](https://github.com/ndmitchell/offline-stack) project and this
[google groups thread]
(https://groups.google.com/forum/#!topic/haskell-stack/LHG9DSrz8k8).
Special thanks to [Neil Mitchell](https://github.com/ndmitchell) !

### Warning!
Please, do not _overuse_ the downloading procedure from scratch.
Excessive downloads will unreasonably increase load on servers.
