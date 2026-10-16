import 'dart:math';

/// Shown once per finished session. Kept short enough to read in the two
/// seconds someone spends on a celebration screen.
const List<String> motivationalQuotes = [
  'The only bad workout is the one that did not happen.',
  'Discipline is choosing between what you want now and what you want most.',
  'You do not have to be extreme, just consistent.',
  'Strength does not come from what you can do. It comes from doing what you once could not.',
  'Small progress is still progress.',
  'The body achieves what the mind believes.',
  'Sweat is just fat crying.',
  'Your only competition is who you were yesterday.',
  'Wake up. Work out. Look hot. Kick ass.',
  'Nobody ever drowned in sweat.',
  'One more rep. One more day. One more reason.',
  'Success starts with self-discipline.',
  'It never gets easier, you just get stronger.',
  'Train insane or remain the same.',
  'The pain you feel today is the strength you feel tomorrow.',
  'Fall in love with taking care of yourself.',
  'Motivation gets you started. Habit keeps you going.',
  'Nothing will work unless you do.',
  'Do something today that your future self will thank you for.',
  'You are one workout away from a better mood.',
  'Push yourself, because no one else is going to do it for you.',
  'Great things never came from comfort zones.',
  'Take care of your body. It is the only place you have to live.',
  'A little progress each day adds up to big results.',
  'Showing up is half the battle. You just won it.',
];

/// Headline paired with the quote, chosen from how much actually got done so
/// the screen never congratulates a barely-started session as a triumph.
String celebrationHeadline(double completionPercent) {
  if (completionPercent >= 100) return 'Perfect session!';
  if (completionPercent >= 75) return 'Strong work!';
  if (completionPercent >= 40) return 'Solid effort!';
  if (completionPercent > 0) return 'Progress logged!';
  return 'Saved for today';
}

String randomQuote() {
  return motivationalQuotes[Random().nextInt(motivationalQuotes.length)];
}
