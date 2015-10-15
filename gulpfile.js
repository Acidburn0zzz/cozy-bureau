var del    = require('del');
var gulp   = require('gulp');
var coffee = require('gulp-coffee');
var lint   = require('gulp-coffeelint');
var insert = require('gulp-insert');
var mocha  = require('gulp-mocha');
var shell  = require('gulp-shell');


var nwVersion = '0.12.3';  // TODO use the version from package.json
var paths = {
  scripts: ['backend/**/*.coffee'],
  scriptsJS: ['bin/cli.js', 'backend/**/*.js'],
  bin: ['bin/cli.js'],
  tests: ['tests/unit/**/*.coffee'],
  all: ["backend/**/*.js", "client/public/**", "app.html", "package.json",
        "node_modules/**"]
};


gulp.task('clean', function(cb) {
  del(paths.scriptsJS).then(function(paths) {
    cb();
  });
});


gulp.task('scripts', ['clean'], function() {
  gulp.src(paths.scripts)
    .pipe(coffee({bare: true}))
    .pipe(gulp.dest('backend'));
});


gulp.task('bin-scripts', function() {
  gulp.src("bin/cli.coffee")
    .pipe(coffee({bare: true}))
    .pipe(insert.prepend('#!/usr/bin/env node\n'))
    .pipe(gulp.dest('bin/'));
});

gulp.task('build-package', ['clean', 'scripts', 'bin-scripts']);

gulp.task('build-gui-package', ['scripts'], function() {
  var NwBuilder = require('nw-builder');
  var nw = new NwBuilder({
      files: paths.all,
      version: nwVersion,
      macIcns: 'packaging/nw.icns',
      platforms: ['linux', 'osx32']
  });
  nw.on('log', console.log.bind(console));
  nw.build().then(function () {
     console.log('Cozy Desktop was successfully built.');
  }).catch(function (error) {
     console.log('An error occured whild building Cozy Desktop:');
     console.log(error);
  });
});


gulp.task('make-deb-32', shell.task([
  'rm -rf pkg_tree',
  'mkdir -p pkg_tree/opt/cozy-desktop pkg_tree/usr/share/doc/cozy-desktop pkg_tree/usr/share/applications',
  'install -b -o root -g root -m 0755 build/cozy-desktop/linux32/* pkg_tree/opt/cozy-desktop/',
  'install -b -o root -g root -m 0644 packaging/icon.png pkg_tree/usr/share/doc/cozy-desktop/',
  'install -b -o root -g root -m 0644 packaging/cozy-desktop.desktop pkg_tree/usr/share/applications/',
  '/bin/sh packaging/create_deb i386'
]));

gulp.task('make-deb-64', shell.task([
  'rm -rf pkg_tree',
  'mkdir -p pkg_tree/opt/cozy-desktop pkg_tree/usr/share/doc/cozy-desktop pkg_tree/usr/share/applications',
  'install -b -o root -g root -m 0755 build/cozy-desktop/linux64/* pkg_tree/opt/cozy-desktop/',
  'install -b -o root -g root -m 0644 packaging/icon.png pkg_tree/usr/share/doc/cozy-desktop/',
  'install -b -o root -g root -m 0644 packaging/cozy-desktop.desktop pkg_tree/usr/share/applications/',
  '/bin/sh packaging/create_deb amd64'
]));

gulp.task('make-rpm-32', shell.task([
  'rm -rf pkg_tree',
  'mkdir -p pkg_tree/opt/cozy-desktop pkg_tree/usr/share/doc/cozy-desktop pkg_tree/usr/share/applications',
  'install -b -o root -g root -m 0755 build/cozy-desktop/linux32/* pkg_tree/opt/cozy-desktop/',
  'install -b -o root -g root -m 0644 packaging/icon.png pkg_tree/usr/share/doc/cozy-desktop/',
  'install -b -o root -g root -m 0644 packaging/cozy-desktop.desktop pkg_tree/usr/share/applications/',
  '/bin/sh packaging/create_rpm i386'
]));

gulp.task('make-rpm-64', shell.task([
  'rm -rf pkg_tree',
  'mkdir -p pkg_tree/opt/cozy-desktop pkg_tree/usr/share/doc/cozy-desktop pkg_tree/usr/share/applications',
  'install -b -o root -g root -m 0755 build/cozy-desktop/linux64/* pkg_tree/opt/cozy-desktop/',
  'install -b -o root -g root -m 0644 packaging/icon.png pkg_tree/usr/share/doc/cozy-desktop/',
  'install -b -o root -g root -m 0644 packaging/cozy-desktop.desktop pkg_tree/usr/share/applications/',
  '/bin/sh packaging/create_rpm amd64'
]));

gulp.task('make-osx-app', shell.task([
  'cp -a build/cozy-desktop/osx32/cozy-desktop.app .'
]));


gulp.task('lint', function() {
  gulp.src(paths.scripts)
    .pipe(lint())
    .pipe(lint.reporter())
});

gulp.task('test', function() {
  require('coffee-script/register');
  process.env.DEFAULT_DIR = 'tmp';
  gulp.src(paths.tests, {
    read: false
  }).pipe(mocha({
    reporter: 'spec'
  }));
});

gulp.task('watch', function() {
  gulp.watch(paths.scripts, ['lint', 'test', 'scripts']);
  gulp.watch('bin/cli.coffee', ['lint', 'bin-scripts']);
});


gulp.task('default',  ['build-package', 'watch']);
