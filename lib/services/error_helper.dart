String cleanErrorMessage(dynamic e) {
  final str = e.toString();
  if (str.contains('SocketException') || 
      str.contains('SocketFailed') || 
      str.contains('host lookup') ||
      str.contains('No address associated with hostname') ||
      str.contains('errno = 7') ||
      str.contains('errno = 110') ||
      str.contains('Connection closed before full header was received')) {
    return 'Network connection failed. Please check your internet connection and try again.';
  }
  if (str.contains('TimeoutException') || str.contains('timeout')) {
    return 'Connection timed out. Please check your internet speed and try again.';
  }
  return str.replaceAll('Exception: ', '');
}
