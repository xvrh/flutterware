
# Flutter Studio

A set of tools for Flutter projects.

## Quick start

Add the `pub`dependency in your `pubspec.yaml`

`flutter pub add flutter_studio`

```yaml
dependencies:
  flutter_studio:
```

Run the GUI app

```shell
# Run this in your Flutter project directory
dart run flutter_studio app
```
The first launch is a bit slow because the tool need to be compiled.

**screenshots**

## Features

### Test visualizer

A new kind of testing built on top of the standard `flutter_test` framework:

- Screenshot every step of your test
- Hot-reload the test instantly (~1s) after any change
- Preview your app with all screen sizes and in all languages
- Easy to write tests that exercise the whole app

### Dependency manager

Overview of your dependencies to monitor the quality.

- See Pub & GitHub scores
- Run `pub upgrade` and preview all changelogs. 

### App icon change

### More tools to come...

Any contribution is welcome.  
Open GitHub issues and pull requests with your ideas :-)