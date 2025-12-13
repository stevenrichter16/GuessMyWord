# TODO

- Restart confirmation in dark mode should use a purple accent.
- Move the current sidebar options into a tab bar that’s hidden by default; tapping the bottom ellipses reveals the tab bar sliding up from the bottom.
- Remove current options from the tab bar before refactoring the sidebar into the tab bar.
- Add Replay feature (new page):
  - Show an “All Animals” circle first.
  - Present the first question with non-tappable Yes/No buttons.
  - Animate the tapped answer button (expand briefly).
  - New top-candidate animal avatars emerge from the All Animals circle and hover gently.
  - Present the next question and Yes/No buttons; animate the chosen answer.
  - If prior top candidates drop out, their avatars get pulled back into the All Animals circle; new top candidates emerge.
  - Repeat for all questions; each question segment lasts ~3 seconds from appearance to candidate updates.
