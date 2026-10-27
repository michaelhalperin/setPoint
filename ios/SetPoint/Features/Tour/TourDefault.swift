import Foundation

/// The tour the app falls back to before it has ever heard from the server (first launch,
/// offline). A copy of the server's built-in tour (backend/src/tour); what the owner saves in
/// /admin replaces it as soon as the app has fetched it once.
enum TourDefault {
    static let json = #"""
{
  "revision": 1,
  "steps": [
    {
      "id": "welcome",
      "anchor": null,
      "welcome": true,
      "title": "Welcome to SetPoint",
      "body": "A 30-second look at where everything is. You can replay it any time from the You tab.",
      "he": {
        "title": "ברוכים הבאים ל-SetPoint",
        "body": "סיור של 30 שניות במה שיש ואיפה. אפשר להפעיל אותו שוב בכל רגע מלשונית אתה."
      },
      "pad": null,
      "radius": null
    },
    {
      "id": "orb",
      "anchor": "today.orb",
      "welcome": false,
      "title": "Your day so far",
      "body": "The number is what you’ve eaten today. The ring fills toward today’s target.",
      "he": {
        "title": "היום שלך עד עכשיו",
        "body": "המספר הוא מה שאכלת היום. הטבעת מתמלאת לקראת היעד של היום."
      },
      "pad": 8,
      "radius": 150
    },
    {
      "id": "next",
      "anchor": "today.next",
      "welcome": false,
      "title": "One thing to do next",
      "body": "Whatever needs you right now shows up here. Log it, swap it, or top up with something easy.",
      "he": {
        "title": "דבר אחד לעשות עכשיו",
        "body": "כל מה שצריך אותך כרגע מופיע כאן. תעד, החלף, או השלם עם משהו קל."
      },
      "pad": 6,
      "radius": 30
    },
    {
      "id": "dots",
      "anchor": "today.dots",
      "welcome": false,
      "title": "Your meal times",
      "body": "Filled dots are meals you’ve had. The empty one is coming up.",
      "he": {
        "title": "שעות הארוחות",
        "body": "נקודות מלאות הן ארוחות שאכלת. הריקה עוד לפניך."
      },
      "pad": 8,
      "radius": 18
    },
    {
      "id": "plus",
      "anchor": "nav.plus",
      "welcome": false,
      "title": "Log from anywhere",
      "body": "Tap + to log a meal by text, photo or barcode.",
      "he": {
        "title": "תעד מכל מקום",
        "body": "לחץ על + כדי לתעד ארוחה בטקסט, בתמונה או בברקוד."
      },
      "pad": 6,
      "radius": 40
    },
    {
      "id": "week",
      "anchor": "train.week",
      "welcome": false,
      "title": "Plan your week",
      "body": "Your training days. Tap + at the top to add a session, and set it to repeat weekly.",
      "he": {
        "title": "תכנן את השבוע",
        "body": "ימי האימון שלך. לחץ על + למעלה כדי להוסיף אימון, ואפשר להגדיר שיחזור כל שבוע."
      },
      "pad": 4,
      "radius": 30
    },
    {
      "id": "day",
      "anchor": "train.day",
      "welcome": false,
      "title": "Training raises your target",
      "body": "On a session day you’re told how much extra to eat, and when to eat it before and after.",
      "he": {
        "title": "אימון מעלה את היעד",
        "body": "ביום אימון תראה כמה עוד כדאי לאכול, ומתי לפני ואחרי."
      },
      "pad": 4,
      "radius": 32
    },
    {
      "id": "weight",
      "anchor": "progress.weight",
      "welcome": false,
      "title": "Are you gaining?",
      "body": "Your weight against the line to your goal. Weigh in here to keep it honest.",
      "he": {
        "title": "האם אתה עולה?",
        "body": "המשקל שלך מול הקו אל היעד. שקול את עצמך כאן כדי לשמור על דיוק."
      },
      "pad": 4,
      "radius": 30
    },
    {
      "id": "closed",
      "anchor": "progress.days",
      "welcome": false,
      "title": "Did the gap close?",
      "body": "A full orb is a day you got enough. Half-filled shows how short it was.",
      "he": {
        "title": "האם הפער נסגר?",
        "body": "כדור מלא הוא יום שאכלת בו מספיק. חצי מלא מראה בכמה פספסת."
      },
      "pad": 4,
      "radius": 30
    },
    {
      "id": "setup",
      "anchor": "you.setup",
      "welcome": false,
      "title": "Make it yours",
      "body": "Meal times, appetite, foods you avoid. Change these and your plan follows.",
      "he": {
        "title": "התאם אישית",
        "body": "שעות ארוחה, תיאבון, מאכלים שאתה נמנע מהם. שנה אותם והתוכנית תעקוב."
      },
      "pad": 6,
      "radius": 30
    },
    {
      "id": "help",
      "anchor": "you.help",
      "welcome": false,
      "title": "Replay this any time",
      "body": "Open this row whenever you want the tour again.",
      "he": {
        "title": "הפעל שוב בכל רגע",
        "body": "פתח את השורה הזו בכל פעם שתרצה את הסיור שוב."
      },
      "pad": 4,
      "radius": 30
    }
  ]
}
"""#
}
