import 'package:flutter_riverpod/flutter_riverpod.dart';

enum UiState {
  idle,
  listening,
  processing,
  responding,
  error,
}

class UiStateNotifier extends StateNotifier<UiState> {
  UiStateNotifier() : super(UiState.idle);

  void setIdle() => state = UiState.idle;
  void setListening() => state = UiState.listening;
  void setProcessing() => state = UiState.processing;
  void setResponding() => state = UiState.responding;
  void setError() => state = UiState.error;
}

final uiStateProvider = StateNotifierProvider<UiStateNotifier, UiState>((ref) {
  return UiStateNotifier();
});
