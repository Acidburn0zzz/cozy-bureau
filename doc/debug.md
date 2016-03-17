Tools for debugging
===================

Bugs can happen. Cozy-desktop has some tools to track them.


Debug logs
----------

The first and most important one is logging. If you think you might have found
a bug, the first thing to do is running cozy-desktop with debug:

```bash
DEBUG=true cozy-desktop sync
```

To keep logs on a file and also display them on screen, you can use `tee`:

```bash
DEBUG=true cozy-desktop sync 2>&1 | tee $(date '+%Y-%m-%d.log')
```

It's possible to have even more logs if you want, by enabling pouchdb debug
logs and request debug logs:

```bash
NODE_DEBUG=request DEBUG=pouchdb:* cozy-desktop sync
```

When cozy-desktop is running, it's possible to send it the `USR1` signal to
make it list the paths watched by chokidar:

```bash
kill -USR1 <pid>
```

And after you stopped cozy-desktop, you can examine its pouchdb database (a
copy in fact) with fauxton:

```bash
bin/fauxton.coffee
```

Don't forget to kill pouchdb-server when you are done.


Debug coffeescript
------------------

You can launch cozy-desktop directly in coffee:

```bash
DEBUG=true node_modules/.bin/coffee src/bin/cli.coffee sync
```
