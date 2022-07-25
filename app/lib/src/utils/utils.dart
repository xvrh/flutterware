

String getSizeAsMB(int bytesLength) {
  return '${(bytesLength / (1024 * 1024)).toStringAsFixed(1)}MB';
}