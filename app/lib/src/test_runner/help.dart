import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: Card(
        child: Markdown(
          data: '''
TAKE FROM DOCUMENTATION
          
## App test
<screenshot dual code <-> result>

### Features
##### Instant hot reload of the code and preview of the result.

##### Choose language, screen size & accessibility features



### Example
[Create an example](#create)

```dart
void main() {

}
```
    
''',
        ),
      ),
    );
  }
}
