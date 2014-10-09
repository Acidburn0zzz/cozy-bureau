var gulp = require('gulp');
var coffee = require('gulp-coffee');
var shell = require('gulp-shell');
var zip = require('gulp-zip');
var concat = require('gulp-concat');
var del = require('del');

var nwVersion = '0.8.6';
var paths = {
  scripts: ['backend/*.coffee'],
  scriptsJS: ['backend/*.js'],
  all: ["backend/**/*.js", "client/public/**", "app.html", "package.json",
        "node_modules/**"],
  leveldown: 'node_modules/pouchdb/node_modules/leveldown'
};


gulp.task('clean', function(cb) {
  del(paths.scriptsJS, cb);
});

gulp.task('scripts', ['clean'], function() {
  return gulp.src(paths.scripts)
    .pipe(coffee({bare: true}))
    .pipe(gulp.dest('backend'));
});

gulp.task('watch', function() {
  gulp.watch(paths.scripts, ['scripts']);
});

gulp.task('leveldown', shell.task([
  'cd ' + paths.leveldown + ' && nw-gyp configure --target=' + nwVersion,
  'cd ' + paths.leveldown + ' && nw-gyp build'
]));

gulp.task('builder', ['scripts', 'leveldown'], function() {
  var NwBuilder = require('node-webkit-builder');
  var nw = new NwBuilder({
      files: paths.all,
      version: nwVersion,
      platforms: ['linux64']
  });
  nw.build().then(function () {
     console.log('Cozy Data Proxy was successfully built.');
  }).catch(function (error) {
     console.log('An error occured whild building Cozy Data Proxy.');
     console.log(error);
  });
});


gulp.task('default',  ['watch']);
