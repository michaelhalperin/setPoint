#!/usr/bin/env python3
"""Adds the Hebrew strings the first catalog pass missed (new keys + translations).

Idempotent: re-running rewrites the same entries. Format specifiers must match the key.
"""
from __future__ import annotations

import json
from pathlib import Path

CATALOG = Path(__file__).resolve().parents[1] / "SetPoint/Shared/Localizable.xcstrings"

HE: dict[str, str] = {}


def add(pairs: str) -> None:
    for line in pairs.strip("\n").split("\n"):
        if not line.strip():
            continue
        en, he = line.split(" ⇒ ", 1)
        HE[en] = he


# --- batches ---------------------------------------------------------------

add("""
Didn’t save ⇒ לא נשמר
Now ⇒ עכשיו
2 hours ⇒ שעתיים
After %@ ⇒ אחרי %@
Back at %@. ⇒ אחזור ב-%@.
I’ll stay quiet till then. ⇒ אשאר בשקט עד אז.
From your photo ⇒ מהתמונה שלך
Working it out… ⇒ מחשב…
No connection. Saved on this phone — it sends when you’re back online. ⇒ אין חיבור. נשמר בטלפון ויישלח כשתחזור לרשת.
%@ (rough estimate) ⇒ %@ (הערכה גסה)
""")

add("""
1 event ⇒ אירוע אחד
%lld events ⇒ %lld אירועים
Less %@ ⇒ פחות %@
More %@ ⇒ יותר %@
Appetite over four weeks ⇒ התיאבון לאורך ארבעה שבועות
too short ⇒ קצר מדי
off ⇒ כבוי
usual time ⇒ שעה רגילה
%@ · missed ⇒ %@ · פוספס
 · kept ⇒  · נשמר
 · missed ⇒  · פוספס
Check in later ⇒ תזכורת מאוחר יותר
More time before a meal counts as slipped ⇒ יותר זמן לפני שארוחה נחשבת מפוספסת
Can you check in later? I need more time around my meals. ⇒ אפשר לשלוח תזכורת מאוחר יותר? אני צריך יותר זמן סביב הארוחות.
Ease the target ⇒ הקל על היעד
A lower number for a while ⇒ מספר נמוך יותר לזמן מה
Can we ease my target for a while? ⇒ אפשר להקל על היעד שלי לזמן מה?
Pause for a few days ⇒ השהיה לכמה ימים
I’ll pick it back up ⇒ אחזור לזה אחר כך
Can we pause check-ins for a few days? ⇒ אפשר להשהות את התזכורות לכמה ימים?
Done. ⇒ בוצע.
Sorted ⇒ סודר
, %lld calories ⇒ , %lld קלוריות
Clear this chat? ⇒ למחוק את השיחה?
Clear chat ⇒ מחק שיחה
AI · not a dietitian ⇒ AI · לא דיאטן
Couldn’t reach the assistant ⇒ לא הצלחתי להגיע לעוזר
The assistant is paused ⇒ העוזר מושהה
Not available for you yet ⇒ עדיין לא זמין עבורך
Part of Pro ⇒ חלק מ-Pro
It sees today’s meals and your targets. ⇒ הוא רואה את הארוחות של היום ואת היעדים שלך.
It suggests a plate. Nothing is logged until you tap Log it. ⇒ הוא מציע מנה. שום דבר לא מתועד עד שתלחץ על "תעד".
It’s AI, not a dietitian. For medical questions, ask a professional. ⇒ זה AI, לא דיאטן. לשאלות רפואיות, פנה לאיש מקצוע.
Today’s target is met ⇒ היעד להיום הושג
What should I eat next? ⇒ מה כדאי לי לאכול עכשיו?
%@ kcal left today. Ask about food, or start with one of these. ⇒ נשארו %@ קלוריות להיום. שאל על אוכל, או התחל באחת מאלה.
Today’s target is met. Ask about food, or start with one of these. ⇒ היעד להיום הושג. שאל על אוכל, או התחל באחת מאלה.
Ask about today’s food, or start with one of these. ⇒ שאל על האוכל של היום, או התחל באחת מאלה.
You: %@ ⇒ אתה: %@
Fits %@ of your %@ kcal left ⇒ מתאים: %1$@ מתוך %2$@ קלוריות שנשארו
%lld grams protein, %lld carbs, %lld fat ⇒ %lld גרם חלבון, %lld פחמימות, %lld שומן
Send ⇒ שלח
AI can be wrong. Not medical advice. ⇒ AI יכול לטעות. לא ייעוץ רפואי.
Now ⇒ עכשיו
%@ servings ⇒ %@ מנות
1 serving ⇒ מנה אחת
%@ eaten. ⇒ נאכלו %@.
+%@ over ⇒ +%@ מעל
Updating meal times ⇒ מעדכן את זמני הארוחות
eaten ⇒ נאכל
due now ⇒ מגיע עכשיו
missed ⇒ פוספס
Eating it · %@ kcal ⇒ אוכל את זה · %@ קלוריות
of %lld g protein ⇒ מתוך %lld גרם חלבון
%@ is next at %@. ⇒ %1$@ הבא ב-%2$@.
Meals you log land here, under their meal time. ⇒ ארוחות שתתעד יופיעו כאן, תחת זמן הארוחה.
%@, %lld calories ⇒ %@, %lld קלוריות
Logged · %lld kcal ⇒ תועד · %lld קלוריות
 · check-in answered ⇒  · התזכורת נענתה
Add %lld kcal ⇒ הוסף %lld קלוריות
this meal ⇒ ארוחה הזו
Add this now. ⇒ הוסף את זה עכשיו.
Add this to %@. ⇒ הוסף את זה ל%@.
You burn %@. ⇒ אתה שורף %@.
over ⇒ מעל
under ⇒ מתחת
 · %lld g protein ⇒  · %lld גרם חלבון
14 lb ⇒ 14 פאונד
6 kg ⇒ 6 ק״ג
%lld cm ⇒ %lld ס״מ
Shorter isn’t always safe ⇒ קצר יותר זה לא תמיד בטוח
%@ covered. ⇒ %@ מכוסה.
A snack later covers it. ⇒ נשנוש מאוחר יותר יסגור את זה.
That’s the gap closed. ⇒ הפער נסגר.
Good swap. ⇒ החלפה טובה.
This one fills it. ⇒ זה ימלא את זה.
NONE ON OUR LIST WITHIN 3 KM ⇒ אין ברשימה שלנו עד 3 ק״מ
%lld PLACES WITHIN 3 KM ⇒ %lld מקומות עד 3 ק״מ
SAMPLE PLACES ⇒ מקומות לדוגמה
WITHIN 3 KM ⇒ עד 3 ק״מ
FILLS IT ⇒ ממלא את זה
Nothing on our list near you yet. ⇒ עדיין אין ברשימה שלנו משהו לידך.
Here’s what to look for. Wolt shows what’s open around you. ⇒ הנה מה לחפש. Wolt מראה מה פתוח סביבך.
Or look for ⇒ או חפש
Calories are a typical estimate for this kind of dish. SetPoint never orders, pays, or sees your Wolt account. ⇒ הקלוריות הן הערכה טיפוסית למנה מהסוג הזה. SetPoint אף פעם לא מזמינה, לא משלמת ולא רואה את חשבון ה-Wolt שלך.
LOOK FOR ⇒ מה לחפש
Search ⇒ חיפוש
Search Wolt for %@ ⇒ חפש ב-Wolt: %@
Sample dish: the live list opens Wolt on %@. ⇒ מנה לדוגמה: ברשימה החיה נפתח Wolt על %@.
%@ logged · %@ kcal ⇒ %1$@ תועד · %2$@ קלוריות
%@ logged · %@ kcal toward %@ ⇒ %1$@ תועד · %2$@ קלוריות לעבר %3$@
Couldn’t get your location. Check that Location Services are on. ⇒ לא הצלחתי לקבל את המיקום שלך. בדוק ששירותי המיקום פועלים.
Day %lld ⇒ יום %lld
After the %lld-day free trial, %@ per year, charged to your Apple ID. Renews automatically unless cancelled at least 24 hours before the period ends. Manage or cancel in Apple ID settings. ⇒ אחרי %lld ימי הניסיון בחינם, %@ לשנה, בחיוב ל-Apple ID שלך. מתחדש אוטומטית אלא אם בוטל לפחות 24 שעות לפני סוף התקופה. ניהול או ביטול בהגדרות Apple ID.
After the %lld-day free trial, %@ per month, charged to your Apple ID. Renews automatically unless cancelled at least 24 hours before the period ends. Manage or cancel in Apple ID settings. ⇒ אחרי %lld ימי הניסיון בחינם, %@ לחודש, בחיוב ל-Apple ID שלך. מתחדש אוטומטית אלא אם בוטל לפחות 24 שעות לפני סוף התקופה. ניהול או ביטול בהגדרות Apple ID.
%@ per year, charged to your Apple ID. Renews automatically unless cancelled at least 24 hours before the period ends. Manage or cancel in Apple ID settings. ⇒ %@ לשנה, בחיוב ל-Apple ID שלך. מתחדש אוטומטית אלא אם בוטל לפחות 24 שעות לפני סוף התקופה. ניהול או ביטול בהגדרות Apple ID.
%@ per month, charged to your Apple ID. Renews automatically unless cancelled at least 24 hours before the period ends. Manage or cancel in Apple ID settings. ⇒ %@ לחודש, בחיוב ל-Apple ID שלך. מתחדש אוטומטית אלא אם בוטל לפחות 24 שעות לפני סוף התקופה. ניהול או ביטול בהגדרות Apple ID.
%@/year ⇒ %@/שנה
%@/month ⇒ %@/חודש
%lld DAYS FREE ⇒ %lld ימים חינם
FREE TRIAL ⇒ ניסיון חינם
%lld wk ⇒ %lld שב׳
easier to eat ⇒ קל יותר לאכול
faster, a bit more food ⇒ מהר יותר, קצת יותר אוכל
or set the weeks yourself ⇒ או קבע את השבועות בעצמך
SetPoint %@ ⇒ SetPoint %@
Your name ⇒ השם שלך
%@, %@. Opens your details ⇒ %1$@, %2$@. פותח את הפרטים שלך
%@. Opens your details ⇒ %@. פותח את הפרטים שלך
Y ⇒ א
Target %@ → %@ kg ⇒ יעד %1$@ ← %2$@ ק״ג
Timeframe %lld → %lld weeks ⇒ מסגרת זמן %1$lld ← %2$lld שבועות
Daily target %@ → %@ kcal ⇒ יעד יומי %1$@ ← %2$@ קלוריות
Your daily target will be recalculated. ⇒ היעד היומי שלך יחושב מחדש.
TODAY ⇒ היום
Tonight ⇒ הערב
Today closes ⇒ היום נסגר
Sunday ⇒ יום ראשון
After 7 days ⇒ אחרי 7 ימים
One thing to fix ⇒ דבר אחד לתקן
%@ of %@. ⇒ %1$@ מתוך %2$@.
%@. ⇒ %@.
Move to %@ ⇒ העבר ל-%@
Weight %@ %@ ⇒ משקל %1$@ %2$@
unknown ⇒ לא ידוע
%@ %@ a week ⇒ %1$@ %2$@ בשבוע
gaining %@ ⇒ עלייה של %@
losing %@ ⇒ ירידה של %@
Today,  ⇒ היום, 
, has a session ⇒ , יש אימון
A snack around %@, a refuel by %@, and a bigger dinner. I’ll nudge you before if you haven’t eaten. ⇒ נשנוש בסביבות %1$@, תדלוק עד %2$@, וארוחת ערב גדולה יותר. אזכיר לך לפני כן אם לא אכלת.
The target stays the same, but I’ll still plan a snack before and a refuel by %@. ⇒ היעד נשאר אותו דבר, אבל עדיין אתכנן נשנוש לפני ותדלוק עד %@.
%@s, from %@ ⇒ בכל %1$@, מ-%2$@
Save · %lld sessions ⇒ שמור · %lld אימונים
Only %@ ⇒ רק %@
%@ and after ⇒ %@ והלאה
PULLING IN THIS WEEK ⇒ נכנס השבוע
Loading train ⇒ טוען את האימונים
refueled ⇒ תודלק
missed the refuel ⇒ פספסת את התדלוק
refuel now ⇒ לתדלק עכשיו
planned ⇒ מתוכנן
Something light — fuel without feeling full. ⇒ משהו קל — דלק בלי להרגיש שבע.
%@ — you’ve had this before a session. ⇒ %@ — אכלת את זה לפני אימון.
%@ — one of your plates. ⇒ %@ — אחת המנות שלך.
%@ — light, and it fits what you eat. ⇒ %@ — קל, ומתאים למה שאתה אוכל.
Nothing logged before — that’s fine. The refuel matters more. ⇒ לא תועד דבר לפני — זה בסדר. התדלוק חשוב יותר.
Apple Health adds it when your watch saves it. ⇒ הבריאות של Apple מוסיפה את זה כשהשעון שומר אותו.
From Apple Health. ⇒ מהבריאות של Apple.
Something with protein within %lld min of finishing — chocolate milk or a sandwich. I’ll remind you. ⇒ משהו עם חלבון תוך %lld דקות מסיום — שוקו או כריך. אזכיר לך.
Missed the window — still eat something with protein now. ⇒ פספסת את החלון — עדיין כדאי לאכול משהו עם חלבון עכשיו.
Your usual dinner plus a side. ⇒ ארוחת הערב הרגילה שלך ועוד תוספת.
Your usual dinner. ⇒ ארוחת הערב הרגילה שלך.
Opens the snack ⇒ פותח את הנשנוש
Logging… ⇒ מתעד…
%@ + %lld more ⇒ %1$@ + עוד %2$lld
%lld kcal at %@ — within the window. ⇒ %1$lld קלוריות ב-%2$@ — בתוך החלון.
You ate within the window. ⇒ אכלת בתוך החלון.
Nothing logged within %lld min of finishing. Next time, a drink counts. ⇒ לא תועד דבר תוך %lld דקות מסיום. בפעם הבאה, גם שתייה נחשבת.
%@, %lld min ⇒ %1$@, %2$lld דק׳
by %@ ⇒ עד %@
%@ · %lld kcal ⇒ %1$@ · %2$lld קלוריות
You’ve had this before a session. ⇒ אכלת את זה לפני אימון.
One of your plates. ⇒ אחת המנות שלך.
Light, and it fits what you eat. ⇒ קל, ומתאים למה שאתה אוכל.
%@ · every %@ ⇒ %1$@ · כל %2$@
%@ · once ⇒ %@ · פעם אחת
Dinner at %@ covers it ⇒ ארוחת הערב ב-%@ מכסה את זה
Looking at today ⇒ מסתכל על היום
Building a plate ⇒ מרכיב מנה
Checking ⇒ בודק
I ate this ⇒ אכלתי את זה
In 1 hour ⇒ בעוד שעה
Remind me ⇒ הזכר לי
After this block ⇒ אחרי הבלוק הזה
Dinner covers it ⇒ ארוחת הערב מכסה את זה
Plans aren't available right now. Try again in a moment. ⇒ התוכניות לא זמינות כרגע. נסה שוב בעוד רגע.
No active subscription found for this Apple ID. ⇒ לא נמצא מנוי פעיל ל-Apple ID הזה.
The App Store couldn't confirm this purchase. ⇒ ה-App Store לא הצליח לאשר את הרכישה הזו.
Two days left on your trial ⇒ נשארו יומיים לתקופת הניסיון
SetPoint bills on day %lld unless you cancel in Apple ID settings. ⇒ SetPoint מחייבת ביום %lld אלא אם תבטל בהגדרות Apple ID.
""")

# Strings that reach the screen as plain `String`s (headline tails, component
# parameters) and are looked up at run time.
add("""
One tap. ⇒ לחיצה אחת.
No password. ⇒ בלי סיסמה.
Let’s fix the plan, not you. ⇒ בואו נתקן את התוכנית, לא אותך.
Two ways to get it in. ⇒ שתי דרכים להכניס את זה.
Logging ⇒ מתעד
Saved here, sent later ⇒ נשמר כאן, נשלח אחר כך
Run on this phone ⇒ רצות בטלפון הזה
Your plan ⇒ התוכנית שלך
From last time ⇒ מהפעם הקודמת
Tap when it’s eaten. ⇒ לחץ כשאכלת.
Eat sooner and I’ll stay quiet. ⇒ תאכל מוקדם יותר ואשאר בשקט.
kcal logged ⇒ קלוריות תועדו
kcal left ⇒ קלוריות נשארו
kcal eaten ⇒ קלוריות נאכלו
Tap, snap or scan it. ⇒ לחץ, צלם או סרוק.
“Two eggs, toast and a latte” ⇒ ״שתי ביצים, טוסט ולאטה״
Clean plate so far. ⇒ צלחת נקייה עד עכשיו.
Say it again ⇒ אמור שוב
No second plate. ⇒ בלי מנה שנייה.
Adding… ⇒ מוסיף…
Learned from you, not guessed. ⇒ נלמד ממך, לא מנחש.
Still learning your burn. ⇒ עדיין לומד כמה אתה שורף.
A few more weeks of meals and weigh-ins. ⇒ עוד כמה שבועות של ארוחות ושקילות.
Logged days ⇒ ימים מתועדים
Weigh-ins ⇒ שקילות
At most 4 a day, and only if a plate slips ⇒ לכל היותר 4 ביום, ורק אם מנה מתפספסת
Answer from the lock screen in one tap ⇒ ענה ממסך הנעילה בלחיצה אחת
Let me reach you. ⇒ תן לי להגיע אליך.
Only when a meal slips. ⇒ רק כשארוחה מתפספסת.
Three plates. ⇒ שלוש מנות.
A day ⇒ ליום
Short at night? I’ll help close it. ⇒ חסר בערב? אעזור לסגור את זה.
Spread over the plates ⇒ מתחלק בין המנות
No check-ins. ⇒ בלי תזכורות.
Log when you like. ⇒ תעד מתי שנוח לך.
Six yes-or-no questions. ⇒ שש שאלות כן או לא.
Quick, and only for you. ⇒ מהיר, ורק בשבילך.
Pushing someone to eat isn’t always safe. If it isn’t for you, I stay quiet. ⇒ לדחוף מישהו לאכול זה לא תמיד בטוח. אם זה לא מתאים לך, אשאר בשקט.
No ⇒ לא
Not sure ⇒ לא בטוח
Yes ⇒ כן
Height ⇒ גובה
Activity ⇒ פעילות
Skip ⇒ דלג
Lower target ⇒ יעד נמוך יותר
Raise target ⇒ יעד גבוה יותר
Timeframe ⇒ מסגרת זמן
Type it — I’ll skip it too ⇒ כתוב אותו — גם אותו אדלג
All ⇒ הכול
Bowls ⇒ קערות
Wraps ⇒ לפתות
Plates ⇒ צלחות
Drinks ⇒ שתייה
Location is off for SetPoint. ⇒ המיקום כבוי עבור SetPoint.
Turn it on in Settings to see places near you. It’s only used for this search. ⇒ הפעל אותו בהגדרות כדי לראות מקומות לידך. הוא משמש רק לחיפוש הזה.
Couldn’t find places. ⇒ לא הצלחתי למצוא מקומות.
No places near you yet. ⇒ עדיין אין מקומות לידך.
We’re adding places area by area. Until then, log something you have at home. ⇒ אנחנו מוסיפים מקומות אזור אחר אזור. עד אז, תעד משהו שיש לך בבית.
Nothing of that kind fits nearby. ⇒ שום דבר מהסוג הזה לא מתאים בסביבה.
Try All, or log something you have at home. ⇒ נסה "הכול", או תעד משהו שיש לך בבית.
Fuel the training. ⇒ תדלק את האימונים.
Meal check-ins stay free. ⇒ תזכורות הארוחות נשארות בחינם.
Refuel check-ins after every workout ⇒ תזכורות תדלוק אחרי כל אימון
More food on training days ⇒ יותר אוכל בימי אימון
Eat before you’re busy ⇒ תאכל לפני שאתה עסוק
Yearly ⇒ שנתי
Monthly ⇒ חודשי
Trial starts ⇒ הניסיון מתחיל
Reminder ⇒ תזכורת
Billed ⇒ חיוב
Starting ⇒ מתחיל
Add a plate ⇒ הוסף מנה
Set by you ⇒ נקבע על ידך
From your goal ⇒ לפי המטרה שלך
Deleting ⇒ מוחק
Thirty minutes earlier ⇒ שלושים דקות מוקדם יותר
Thirty minutes later ⇒ שלושים דקות מאוחר יותר
Earlier week ⇒ שבוע קודם
Later week ⇒ שבוע הבא
Training days get more food ⇒ בימי אימון מקבלים יותר אוכל
Your target rises with the session, so the extra burn doesn’t widen the gap. ⇒ היעד שלך עולה עם האימון, כך שהשריפה הנוספת לא מרחיבה את הפער.
Refuel right after ⇒ תדלוק מיד אחרי
When Apple Health saves a workout, a refuel check-in follows within minutes. ⇒ כשהבריאות של Apple שומרת אימון, תזכורת תדלוק מגיעה תוך דקות.
Eat before you train ⇒ תאכל לפני האימון
A nudge before a planned session if you haven’t eaten. ⇒ תזכורת לפני אימון מתוכנן אם לא אכלת.
You trained. ⇒ התאמנת.
Eat something now. ⇒ תאכל משהו עכשיו.
SetPoint is invite-only for now. ⇒ SetPoint בהזמנה בלבד לעת עתה.
Enter your code to get in. ⇒ הזן את הקוד שלך כדי להיכנס.
Eat enough to grow, ⇒ תאכל מספיק כדי לגדול,
without forcing it. ⇒ בלי להכריח את עצמך.
Logged · %@ · %lld kcal ⇒ תועד · %1$@ · %2$lld קלוריות
Saved meal ⇒ ארוחה שמורה
Calories left ⇒ קלוריות שנותרו
Log usual meal ⇒ תעד ארוחה רגילה
Log my usual meal ⇒ תעד את הארוחה הרגילה שלי
Logs one of your saved SetPoint meals. ⇒ מתעד אחת מהארוחות השמורות שלך ב-SetPoint.
Meal ⇒ ארוחה
Which meal ⇒ איזו ארוחה
g ⇒ ג׳
cm ⇒ ס״מ
""")

add("""
You can still log. ⇒ אפשר עדיין לתעד.
Weigh-in. ⇒ שקילה.
Morning, before food. ⇒ בבוקר, לפני האוכל.
Search Wolt for it ⇒ חפש אותו ב-Wolt
The whole product — one deal ⇒ כל המוצר — במחיר אחד
Meal times: %@. Quiet from %@ to %@. ⇒ זמני ארוחות: %1$@. שקט מ-%2$@ עד %3$@.
 Now %@. ⇒  עכשיו %@.
""")

add("""
PROTEIN ⇒ חלבון
CARBS ⇒ פחמימות
FAT ⇒ שומן
""")

add("""
%@ · %lld this week ⇒ %1$@ · %2$lld השבוע
""")

# The staple foods the plate solver draws from (backend/src/data/stapleFoods.ts).
add("""
2 large eggs ⇒ 2 ביצים גדולות
Hard-boiled eggs ⇒ ביצים קשות
Plain nonfat Greek yogurt ⇒ יוגורט יווני רגיל 0%
2% cottage cheese ⇒ קוטג׳ 2%
Whole milk ⇒ חלב מלא
Cheddar cheese ⇒ גבינת צ׳דר
String cheese ⇒ גבינת חוטים
Chicken breast ⇒ חזה עוף
Rotisserie chicken ⇒ עוף צלוי
Ground beef (90% lean) ⇒ בשר בקר טחון (90% רזה)
Deli turkey slices ⇒ פרוסות הודו
Canned tuna in water ⇒ טונה משומרת במים
Salmon fillet ⇒ פילה סלמון
Firm tofu ⇒ טופו קשה
Shelled edamame ⇒ אדממה קלופה
Black beans ⇒ שעועית שחורה
Lentils ⇒ עדשים
Chickpeas ⇒ גרגירי חומוס
Hummus ⇒ חומוס
Almonds ⇒ שקדים
Mixed nuts ⇒ אגוזים מעורבים
Trail mix ⇒ תערובת אגוזים ופירות יבשים
White rice ⇒ אורז לבן
Rolled oats ⇒ שיבולת שועל
Instant oatmeal packet ⇒ שקית דייסת שיבולת שועל מהירה
Whole wheat bread ⇒ לחם מחיטה מלאה
Plain bagel ⇒ בייגל רגיל
Banana ⇒ בננה
Baked potato ⇒ תפוח אדמה אפוי
Sweet potato ⇒ בטטה
Avocado ⇒ אבוקדו
Whey protein shake ⇒ שייק חלבון מי גבינה
Protein bar ⇒ חטיף חלבון
Granola ⇒ גרנולה
Cereal with milk ⇒ דגני בוקר עם חלב
Greek yogurt with granola ⇒ יוגורט יווני עם גרנולה
Peanut butter & banana toast ⇒ טוסט חמאת בוטנים ובננה
Tuna with crackers ⇒ טונה עם קרקרים
Chicken burrito bowl ⇒ קערת בוריטו עוף
3 scrambled eggs ⇒ 3 ביצים מקושקשות
Liquid egg whites ⇒ חלבוני ביצה נוזליים
Whole-milk Greek yogurt ⇒ יוגורט יווני מלא
Skyr ⇒ סקיר
Plain kefir ⇒ קפיר רגיל
2% milk ⇒ חלב 2%
Chocolate milk ⇒ שוקו
Part-skim ricotta ⇒ ריקוטה דלת שומן
Mozzarella ⇒ מוצרלה
Feta ⇒ גבינת פטה
Cream cheese ⇒ גבינת שמנת
Butter ⇒ חמאה
Heavy cream ⇒ שמנת מתוקה
Chicken thigh ⇒ שוק עוף
Ground turkey (93% lean) ⇒ הודו טחון (93% רזה)
Sirloin steak ⇒ סטייק סינטה
Pork tenderloin ⇒ פילה חזיר
Pork chop ⇒ קוטלט חזיר
Sliced ham ⇒ חזיר פרוס
Deli roast beef ⇒ רוסטביף פרוס
Chicken sausage ⇒ נקניקיית עוף
Beef jerky ⇒ בשר מיובש (ג׳רקי)
Canned salmon ⇒ סלמון משומר
Sardines in oil ⇒ סרדינים בשמן
Tilapia fillet ⇒ פילה אמנון
Cooked shrimp ⇒ שרימפס מבושל
Tempeh ⇒ טמפה
Seitan ⇒ סייטן
Soy milk ⇒ משקה סויה
Kidney beans ⇒ שעועית אדומה
Refried beans ⇒ שעועית מטוגנת
Split pea soup ⇒ מרק אפונה
Falafel ⇒ פלאפל
Veggie burger patty ⇒ קציצת המבורגר צמחית
Roasted chickpeas ⇒ חומוס קלוי
Cashews ⇒ קשיו
Walnuts ⇒ אגוזי מלך
Pistachios ⇒ פיסטוקים
Pumpkin seeds ⇒ גרעיני דלעת
Sunflower seeds ⇒ גרעיני חמניות
Almond butter ⇒ חמאת שקדים
Tahini ⇒ טחינה
Chia seeds ⇒ זרעי צ׳יה
Hemp hearts ⇒ גרעיני קנבוס
Brown rice ⇒ אורז מלא
Quinoa ⇒ קינואה
Couscous ⇒ קוסקוס
Farro ⇒ פארו
White bread ⇒ לחם לבן
Sourdough bread ⇒ לחם שאור
English muffin ⇒ מאפין אנגלי
Flour tortilla ⇒ טורטיית קמח
Corn tortillas ⇒ טורטיות תירס
Pita bread ⇒ פיתה
Whole-grain crackers ⇒ קרקרים מדגנים מלאים
Rice cakes ⇒ פריכיות אורז
Pretzels ⇒ פרצלים
Air-popped popcorn ⇒ פופקורן
Mashed potatoes ⇒ פירה
Corn ⇒ תירס
Green peas ⇒ אפונה ירוקה
Dinner roll ⇒ לחמנייה
Pancakes ⇒ פנקייק
Frozen waffles ⇒ וופלים קפואים
Apple ⇒ תפוח
Orange ⇒ תפוז
Grapes ⇒ ענבים
Blueberries ⇒ אוכמניות
Raisins ⇒ צימוקים
Medjool dates ⇒ תמרי מג׳הול
Dried apricots ⇒ משמש מיובש
Applesauce cup ⇒ כוסית מחית תפוחים
Fruit & nut trail mix ⇒ תערובת פירות ואגוזים
Whole avocado ⇒ אבוקדו שלם
Olives ⇒ זיתים
Canned coconut milk ⇒ חלב קוקוס משומר
Mayonnaise ⇒ מיונז
Guacamole ⇒ גואקמולה
Turkey sandwich ⇒ כריך הודו
Peanut butter & jelly sandwich ⇒ כריך חמאת בוטנים וריבה
Grilled cheese ⇒ טוסט גבינה
Bean & cheese burrito ⇒ בוריטו שעועית וגבינה
Cheese pizza ⇒ פיצה גבינה
Macaroni & cheese ⇒ מקרוני וגבינה
Instant ramen ⇒ ראמן מהיר
Chicken noodle soup ⇒ מרק עוף עם אטריות
Canned chili with beans ⇒ צ׳ילי עם שעועית משומר
Lentil soup ⇒ מרק עדשים
Fruit smoothie ⇒ שייק פירות
Protein smoothie ⇒ שייק חלבון
Yogurt & fruit parfait ⇒ פרפה יוגורט ופירות
Apple with peanut butter ⇒ תפוח עם חמאת בוטנים
Cottage cheese with fruit ⇒ קוטג׳ עם פירות
Bagel with cream cheese ⇒ בייגל עם גבינת שמנת
Egg & cheese breakfast sandwich ⇒ כריך בוקר ביצה וגבינה
Egg salad sandwich ⇒ כריך סלט ביצים
Chicken Caesar salad ⇒ סלט קיסר עם עוף
Chicken & rice bowl ⇒ קערת עוף ואורז
Overnight oats ⇒ שיבולת שועל לילה
Ready-to-drink protein shake ⇒ שייק חלבון מוכן לשתייה
Nutrition shake ⇒ שייק תזונתי
Plant protein shake ⇒ שייק חלבון צמחי
""")

add("""
Nothing logged. ⇒ לא תועד כלום.
%lld kcal under target. ⇒ %lld קלוריות מתחת ליעד.
Over target. ⇒ מעל היעד.
On target. ⇒ על היעד.
A salmon or chicken poke bowl ⇒ קערת פוקי סלמון או עוף
A grilled chicken plate with two sides ⇒ צלחת עוף בגריל עם שתי תוספות
A shawarma plate with sides ⇒ צלחת שווארמה עם תוספות
Shawarma in a pita ⇒ שווארמה בפיתה
A schnitzel plate ⇒ צלחת שניצל
Pad thai with chicken ⇒ פאד תאי עם עוף
A big chicken salad ⇒ סלט עוף גדול
A chicken sandwich ⇒ כריך עוף
A tofu poke bowl ⇒ קערת פוקי טופו
Falafel in a pita with hummus ⇒ פלאפל בפיתה עם חומוס
""")

add("""
How it works ⇒ איך זה עובד
Training is half of it. ⇒ האימון הוא חצי מהסיפור.
Eating enough is the other half. ⇒ לאכול מספיק זה החצי השני.
SetPoint watches your day and closes the gap between what you ate and what your training needs. ⇒ SetPoint עוקבת אחרי היום שלך וסוגרת את הפער בין מה שאכלת למה שהאימון שלך דורש.
Your day is one line. ⇒ היום שלך הוא קו אחד.
See where you should be. ⇒ תראה איפה כדאי שתהיה.
The ticks are your meal times and the dots are what you ate. The marker is now. Whatever comes next shows up as a single card. ⇒ הסימנים הם זמני הארוחות, הנקודות הן מה שאכלת, והמחוון הוא עכשיו. מה שבא אחרי מופיע ככרטיס אחד.
Check-ins ⇒ צ׳ק-אינים
Skipped or light? ⇒ דילגת או אכלת קל?
I’ll ask. ⇒ אני אשאל.
When a meal is missed or small, I check in. Log it, swap it, or top up with something easy like milk or nuts. In the evening I close what’s left. ⇒ כשארוחה מתפספסת או קטנה, אני בודק איתך. תרשום אותה, תחליף, או תשלים עם משהו קל כמו חלב או אגוזים. בערב אני סוגר את מה שנשאר.
Training moves your plan. ⇒ האימון מזיז את התוכנית.
Add a session, targets rise. ⇒ מוסיפים אימון, היעדים עולים.
Plan your sessions on the Train tab. Tap + any time to log a meal by text, photo or barcode. ⇒ תכנן את האימונים בלשונית אימון. לחץ על + בכל רגע כדי לרשום ארוחה בטקסט, בתמונה או בברקוד.
Get started ⇒ מתחילים
Needed today ⇒ נדרש היום
Ate ⇒ אכלת
The gap ⇒ הפער
Next: dinner ⇒ הבא: ארוחת ערב
Lunch was light ⇒ ארוחת הצהריים הייתה קלה
A glass of milk and a spoon of peanut butter gets you back on track. ⇒ כוס חלב וכף חמאת בוטנים מחזירות אותך למסלול.
How SetPoint works ⇒ איך SetPoint עובדת
A quick tour ⇒ סיור קצר
""")

add("""
Show me ⇒ הראה לי
Next ⇒ הבא
Show tour as first run ⇒ הצג סיור כבפעם הראשונה
""")

add("""
Top-up: ⇒ תוספת: 
rough estimate ⇒ הערכה גסה
""")

# ---------------------------------------------------------------------------


def apply() -> None:
    data = json.loads(CATALOG.read_text())
    strings = data["strings"]
    for key, he in HE.items():
        entry = strings.setdefault(key, {})
        locs = entry.setdefault("localizations", {})
        if "he" in locs:
            continue
        locs["he"] = {"stringUnit": {"state": "translated", "value": he}}
    # A Hebrew string that opens with a Latin letter or a placeholder would be
    # laid out left to right by the text engine; a leading RLM pins it right to left.
    rlm = "\u200f"
    fixed = 0
    for entry in strings.values():
        unit = entry.get("localizations", {}).get("he", {}).get("stringUnit")
        if not unit:
            continue
        # Arrows point the way the text reads.
        unit["value"] = unit["value"].replace("→", "←")
        value = unit["value"]
        if value and not value.startswith(rlm) and (value[0].isascii() and value[0].isalpha() or value[0] == "%"):
            if any("\u0590" <= c <= "\u05ff" for c in value):
                unit["value"] = rlm + value
                fixed += 1
    CATALOG.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print(f"applied {len(HE)}, rlm {fixed}")


if __name__ == "__main__":
    apply()
