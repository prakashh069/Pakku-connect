import 'package:connecto/core/models/call.dart';

/// A generalized, abstract interface to decouple the UI surface from the CallManager.
abstract class CallPresenter {
  /// Tells the presenter to animate or display the call UI.
  void showCall(Call call);

  /// Tells the presenter to update the UI with new call state (e.g. answered, duration).
  void updateCall(Call call, {int elapsedSeconds = 0});

  /// Tells the presenter to animate out and dismiss the call UI.
  void dismissCall();
}
