void main(List<String> arguments) {
  print('Hello world!');

  // 1. Start a server with a random port
  // 2. Listen on a websocket for the UI to connect (allow multiple UI)
  // 3. For each UI, create a "Client": a flutter run -d flutter-tester process
  //    pointing to an invisible .dart file with the configured entry point.
  //    In the entry point: a websocket url (which contain an id).
  // 4. The client connect in WebSocket back to the server
  // 5. The server put the UI & the client in relation (forward directly the payload)

  // => Goal get the project running

  // Next steps:
  // - Compile the app in web and serve it with the server.
  // - Find stable solution for the fonts (ie. use desktop fonts, fallback to other font, propose to download some fonts etc...).
  // - Re-add email & pdf management
  // - Allow to test (flutter test xx)?
  // - Allow to build web app (+ immediate preview).
}
