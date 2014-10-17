# [Cozy](http://cozy.io) Data Proxy

The Data Proxy allows to sync the files stored in your Cozy with your laptop
and/or your desktop. It replicates your files on your hard drive and report
changes you made on them.

# Workflow

```
cli.coffee add-remote-cozy http://url.of.my.cozy devicename /sync/directory
cli.coffee replicate --fromRemote # Do it only the first time.
cli.coffee sync
```

# TODO

* Investigate on pouchDB listener limit error
* Handle conflicts properly
* Allow files to be added locally while downloading binary from remote


# How to run node-webkit application

1. Download [node-webkit](https://github.com/rogerwang/node-webkit#downloads)
2. unpack downloaded archive
3. On Ubuntu fix [the libudev
   issue](https://github.com/rogerwang/node-webkit/wiki/The-solution-of-lacking-libudev.so.0)
4. In your cozy-data-proxy root folder run:

    path/to/node-webkit/nw .


## What is Cozy?

![Cozy Logo](https://raw.github.com/mycozycloud/cozy-setup/gh-pages/assets/images/happycloud.png)

[Cozy](http://cozy.io) is a platform that brings all your web services in the
same private space.  With it, your web apps and your devices can share data
easily, providing you
with a new experience. You can install Cozy on your own hardware where no one
profiles you.



## Community

You can reach the Cozy Community by:

* Chatting with us on IRC #cozycloud on irc.freenode.net
* Posting on our [Forum](https://forum.cozy.io)
* Posting issues on the [Github repos](https://github.com/mycozycloud/)
* Mentioning us on [Twitter](http://twitter.com/mycozycloud)
