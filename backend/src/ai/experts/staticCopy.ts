import type { ExpertLang } from './kinds.js';

/**
 * Reviewed static copy. Not generated. Professional-help resources are the same
 * generic pointer onboarding uses until counsel names a specific service.
 */
export const COPY = {
  en: {
    title: 'Nutrition assistant · AI',
    paused: 'This is paused.',
    ineligible:
      'From your answers, I won’t push you to eat. If eating feels hard right now, a doctor or an eating-disorder service can help in a way an app can’t.',
    distress:
      'I’m not the right place for this. A doctor or an eating-disorder service can help in a way an app can’t.',
    locked:
      'I’m stepping back for a bit. If eating feels hard, a doctor or an eating-disorder service can help. You can try again later.',
    validatorFail: 'I couldn’t put that together safely. Try a simpler ask, or log from Today.',
    malformed: 'I couldn’t put that together. Try one of the chips below.',
    emptyPlate: 'Nothing in your foods fits that ask. Change Foods I avoid, or try another chip.',
    offRampCheckIns: 'I can’t change check-ins from here. You can snooze or pause in You.',
    offRampMedical: 'I can’t help with that. A qualified professional can.',
    offRampEatLess: 'This app is here to help you eat enough, not eat less.',
    opener: 'What’s left today — a fast plate, something you can drink, or a meal you already like?',
    consentTitle: 'Nutrition assistant · AI',
    consentBody:
      'This is an AI assistant, not a dietitian or a doctor. Your messages and a snapshot of today’s meals, plan, and restrictions are sent to Anthropic to generate a reply. Meal photos are not sent. Your trainer cannot see this. If a message is flagged as unsafe, SetPoint may read that turn to check the safety system. Full-thread review happens only if you opt in below. You can stop by not using this, and you can delete your account in You.',
    consentReview: 'SetPoint may read this whole chat to check it is safe.',
    consentAccept: 'Continue',
    consentDecline: 'Not now',
    stageLook: 'Looking at today',
    stagePlate: 'Building a plate',
    stageCheck: 'Checking',
    chipLeft: 'What’s left today?',
    chipTen: 'I only have 10 minutes',
    chipDrink: 'Something I can drink',
    chipSaved: 'Use a meal I already like',
    confirmTitle: 'Eat this',
    angry: 'I can’t change check-ins from here. You can snooze or pause in You.',
  },
  he: {
    title: 'עוזר תזונה · AI',
    paused: 'זה מושהה כרגע.',
    ineligible:
      'לפי התשובות שלך, לא אדחוף אותך לאכול. אם האכילה קשה עכשיו, רופא או שירות להפרעות אכילה יכולים לעזור בדרך שאפליקציה לא יכולה.',
    distress:
      'אני לא המקום הנכון לזה. רופא או שירות להפרעות אכילה יכולים לעזור בדרך שאפליקציה לא יכולה.',
    locked:
      'אני עוצר לרגע. אם האכילה קשה, רופא או שירות להפרעות אכילה יכולים לעזור. אפשר לנסות שוב אחר כך.',
    validatorFail: 'לא יכולתי להרכיב את זה בבטחה. נסו בקשה פשוטה יותר, או רשמו מהמסך היום.',
    malformed: 'לא הצלחתי להרכיב את זה. נסו אחת מהאפשרויות למטה.',
    emptyPlate: 'אין מאכל שמתאים לבקשה הזו ברשימה שלך. אפשר לשנות ב«מאכלים שאני נמנע», או לנסות אפשרות אחרת.',
    offRampCheckIns: 'אי אפשר לשנות תזכורות מכאן. אפשר לדחות או להשהות במסך אתה.',
    offRampMedical: 'אני לא יכול לעזור בזה. איש מקצוע מוסמך יכול.',
    offRampEatLess: 'האפליקציה הזו כאן כדי לעזור לך לאכול מספיק, לא לאכול פחות.',
    opener: 'מה נשאר היום — צלחת מהירה, משהו לשתות, או ארוחה שכבר אוהבים?',
    consentTitle: 'עוזר תזונה · AI',
    consentBody:
      'זה עוזר AI, לא דיאטן ולא רופא. ההודעות שלך ותמונת מצב של הארוחות, התוכנית וההגבלות של היום נשלחות ל-Anthropic כדי לייצר תשובה. תמונות ארוחה לא נשלחות. המאמן שלך לא רואה את זה. אם הודעה מסומנת כלא בטוחה, SetPoint עשויה לקרוא את התור הזה כדי לבדוק את מערכת הבטיחות. קריאת השיחה המלאה רק אם תבחרו בזה למטה. אפשר להפסיק בזה שלא משתמשים, ואפשר למחוק את החשבון במסך אתה.',
    consentReview: 'SetPoint רשאית לקרוא את כל השיחה הזו כדי לבדוק שהיא בטוחה.',
    consentAccept: 'המשך',
    consentDecline: 'לא עכשיו',
    stageLook: 'מסתכל על היום',
    stagePlate: 'מרכיב צלחת',
    stageCheck: 'בודק',
    chipLeft: 'מה נשאר היום?',
    chipTen: 'יש לי רק 10 דקות',
    chipDrink: 'משהו שאפשר לשתות',
    chipSaved: 'ארוחה שכבר אוהבים',
    confirmTitle: 'לאכול את זה',
    angry: 'אי אפשר לשנות תזכורות מכאן. אפשר לדחות או להשהות במסך אתה.',
  },
} as const;

export function copy(lang: ExpertLang) {
  return COPY[lang] ?? COPY.en;
}

export function chips(lang: ExpertLang) {
  const c = copy(lang);
  return [
    { id: 'left', title: c.chipLeft, message: c.chipLeft },
    { id: 'ten', title: c.chipTen, message: c.chipTen },
    { id: 'drink', title: c.chipDrink, message: c.chipDrink },
    { id: 'saved', title: c.chipSaved, message: c.chipSaved },
  ];
}
