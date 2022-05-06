/*import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

void main() {
  runApp(App());
}

class App extends StatelessWidget {
  const App({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Html(
            data: _email,
          ),
        ),
      ),
    );
  }
}

final _email = '''
<!-- Email subject: Welcome to iAqualink+ App! -->
<!-- Email message: -->
<body style="width: 100%; text-align: center; max-width: 700px; padding-bottom: 50px; margin:auto; font-family: sans-serif; font-size: 16px; color: #38455A; border: solid 1px #DFE3E9; border-radius: 10px"><style>a {  color: #4D93F6; }
</style><center>
<div style="background-image: url('${_readImage('/Users/xavier/Downloads/header.png')}');">
<table style="width: 100%; min-height: 150px; background-image: url('${_readImage('/Users/xavier/Downloads/header.png')}'); background-position: top center; background-size: cover;"><tbody><tr><td style="text-align: center; vertical-align: center;"><h1 style="color: white;">Welcome aboard!</h1></td></tr></tbody></table><div style="max-width: 350px; margin: auto; text-align: center; padding: 10px;"><p>Hello <strong>John</strong>,</p>
<p>Thanks for joining us! Here you will find the activation code to finalize your registration process.</p>
<p>Then you will be ready to start making the most out of your pool &amp; spa with the services available in iAquaLink+ App!</p>
<p style="font-weight: bold; margin-top: 30px;">Your activation code is:</p><div style="font-size: 32px; color: #66D2CC; margin: 10px 0;letter-spacing: 10px"><strong>{####}</strong></div><div style="padding-top: 40px; margin-bottom: 40px"><a style="background-color: #4D93F6;color: white;padding: 15px 15px 15px 40px;text-decoration: none; font-weight: bold; border-radius: 25px;" href="https://iaqualinkplus.page.link?link=http%3A%2F%2Flocalhost%3A8086%2Fpublic%2Fverification-code%3Fcode%3D{####}&amp;apn=com.fluidra.iaqualinkplus&amp;ibi=com.fluidra.iaqualinkplus">ACTIVATE YOUR ACCOUNT</a></div><div>If you think the information in this email is not for you, please ignore it. If an error occurs while resetting your password, please contact us at info@iaqualink.com</div><div style="margin-top: 30px">Greetings</div><div style="font-weight: bold">iAquaLink+ Team</div><hr style="display: block; margin: 30px 0; border: solid 1px #DFE3E9"/><div style="margin-bottom: 40px; color: #6D7783;font-size: 12px;">This email has been sent automatically from an address that does not accept emails. Please do not reply to this email.</div><img src="${_readImage('/Users/xavier/Downloads/header.png')}" alt="iAqualink+ logo" width="155"/></div></body>
</center>
</div>
''';

String _readImage(String path) {
  var bytes = File(path).readAsBytesSync();
  var uri = Uri.dataFromBytes(bytes, mimeType: 'image/png');
  return uri.toString();
}
*/
