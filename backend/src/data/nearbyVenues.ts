import type { NearbyVenue } from '../nearby/index.js';
import { ISRAEL_VENUES } from './nearbyVenuesIsrael.js';

/**
 * The real list: places near our users, their dishes with our kcal and macro
 * estimates (Wolt doesn't publish them), and the Wolt link for each dish.
 * Central Tel Aviv, collected from wolt.com on 2026-10-19 — menus change, so a
 * dish link that stops opening means the dish is gone and should come out.
 * Allergens are read from the menu text; when a menu doesn't say, it's a guess.
 */
const CENTRAL_TEL_AVIV_VENUES: NearbyVenue[] = [
  {
    id: 'wolt-pick-a-poke-tel-aviv',
    name: 'Pick A Poke',
    lat: 32.07911818,
    lng: 34.79495836,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/pick-a-poke-tel-aviv',
    dishes: [
      { id: 'd49a603d8fe4d67d92dcb0fc', name: 'Pick In Japan poke: salmon and tuna, ramen egg, shiitake', kcal: 720, proteinG: 38, carbsG: 88, fatG: 22, kind: 'BOWL', allergens: ['fish', 'egg', 'soy', 'sesame', 'gluten', 'wheat'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/pick-a-poke-tel-aviv/itemid-d49a603d8fe4d67d92dcb0fc' },
      { id: '11f6698807c2b1fdc9c36f16', name: 'Pick In Korea: spicy Korean beef on glass noodles', kcal: 700, proteinG: 36, carbsG: 85, fatG: 24, kind: 'BOWL', allergens: ['soy', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/pick-a-poke-tel-aviv/itemid-11f6698807c2b1fdc9c36f16' },
      { id: '8303959307fdcb5df151c88a', name: 'Summer poke: ramen-style chicken on glass noodles', kcal: 640, proteinG: 40, carbsG: 75, fatG: 18, kind: 'BOWL', allergens: ['soy', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/pick-a-poke-tel-aviv/itemid-8303959307fdcb5df151c88a' },
      { id: 'aa13774d248dd9b74af8ef9e', name: 'Beef banh: slow-cooked curry beef sandwich', kcal: 380, proteinG: 18, carbsG: 40, fatG: 16, kind: 'WRAP', allergens: ['gluten', 'wheat', 'egg', 'soy'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/pick-a-poke-tel-aviv/itemid-aa13774d248dd9b74af8ef9e' },
    ],
  },
  {
    id: 'wolt-pokeshop-rothschild',
    name: 'PokeShop',
    lat: 32.06242717,
    lng: 34.76996899,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/pokeshop-rothschild',
    dishes: [
      { id: '5ce66986cc75e97ec9378a4a', name: 'Salmon poke, large', kcal: 750, proteinG: 38, carbsG: 90, fatG: 25, kind: 'BOWL', allergens: ['fish', 'soy', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/pokeshop-rothschild/itemid-5ce66986cc75e97ec9378a4a' },
      { id: '5ce66986cc75e97ec9378a54', name: 'Tuna poke, large', kcal: 680, proteinG: 42, carbsG: 90, fatG: 14, kind: 'BOWL', allergens: ['fish', 'soy', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/pokeshop-rothschild/itemid-5ce66986cc75e97ec9378a54' },
      { id: 'c1bab3e2f6c2897ac1eefb64', name: 'Teriyaki cooked tuna poke, large', kcal: 700, proteinG: 40, carbsG: 95, fatG: 15, kind: 'BOWL', allergens: ['fish', 'soy', 'gluten', 'wheat', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/pokeshop-rothschild/itemid-c1bab3e2f6c2897ac1eefb64' },
    ],
  },
  {
    id: 'wolt-aloha-sarona',
    name: 'Aloha',
    lat: 32.071094,
    lng: 34.787088,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/aloha-sarona',
    dishes: [
      { id: 'c890c6a15ca6a7ac40d8aaf8', name: 'Miso salmon poke with avocado and edamame', kcal: 720, proteinG: 34, carbsG: 85, fatG: 26, kind: 'BOWL', allergens: ['fish', 'soy', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/aloha-sarona/itemid-c890c6a15ca6a7ac40d8aaf8' },
      { id: '1e84fe97ad932e03d22f9b66', name: 'Kua Moa: pulled chicken stew on rice with a fried egg', kcal: 760, proteinG: 42, carbsG: 85, fatG: 26, kind: 'BOWL', allergens: ['egg', 'soy'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/aloha-sarona/itemid-1e84fe97ad932e03d22f9b66' },
      { id: '48a32b02011c9de083f7819c', name: 'Crunch Honolulu: crispy chicken on rice, spicy mayo', kcal: 900, proteinG: 42, carbsG: 100, fatG: 36, kind: 'BOWL', allergens: ['gluten', 'wheat', 'egg', 'soy', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/aloha-sarona/itemid-48a32b02011c9de083f7819c' },
      { id: '5c3189d6c29bd6e4c09bf095', name: 'Maui salad: chicken, soba noodles, peanuts', kcal: 520, proteinG: 32, carbsG: 50, fatG: 20, kind: 'BOWL', allergens: ['peanut', 'gluten', 'wheat', 'soy', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/aloha-sarona/itemid-5c3189d6c29bd6e4c09bf095' },
    ],
  },
  {
    id: 'wolt-halevantini',
    name: 'Halevantini',
    lat: 32.08705962,
    lng: 34.7732681,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/halevantini',
    dishes: [
      { id: '5c1923811f149d000a567c7e', name: 'Grilled chicken breast plate with hummus, salad and a side', kcal: 820, proteinG: 58, carbsG: 70, fatG: 32, kind: 'PLATE', allergens: ['sesame', 'gluten', 'wheat'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/halevantini/itemid-5c1923811f149d000a567c7e' },
      { id: '5db58833a504cdccee361a7b', name: 'Grilled chicken thighs in laffa with hummus and tahini', kcal: 880, proteinG: 46, carbsG: 82, fatG: 40, kind: 'WRAP', allergens: ['sesame', 'gluten', 'wheat'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/halevantini/itemid-5db58833a504cdccee361a7b' },
      { id: '5c192413cf8956000a6c05d6', name: 'Turkey shawarma plate with hummus, salad and a side', kcal: 900, proteinG: 52, carbsG: 75, fatG: 42, kind: 'PLATE', allergens: ['sesame', 'gluten', 'wheat'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/halevantini/itemid-5c192413cf8956000a6c05d6' },
      { id: '5c191dbdfae37c000c4de8bd', name: 'Hummus with tahini and warm chickpeas, pita on the side', kcal: 650, proteinG: 24, carbsG: 75, fatG: 28, kind: 'BOWL', allergens: ['sesame', 'gluten', 'wheat'], tags: ['vegan'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/halevantini/itemid-5c191dbdfae37c000c4de8bd' },
    ],
  },
  {
    id: 'wolt-congress-basel',
    name: 'Congress Basel',
    lat: 32.089253,
    lng: 34.782489,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/congress-basel',
    dishes: [
      { id: '6438ffc66621a18964944901', name: "Athlete's bowl: 250 g chicken shawarma, boiled egg, salad", kcal: 760, proteinG: 62, carbsG: 35, fatG: 40, kind: 'BOWL', allergens: ['egg', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/congress-basel/itemid-6438ffc66621a18964944901' },
      { id: '61d2b086424b6d8fa6a6129d', name: 'Grilled chicken breast, 250 g, with two sides', kcal: 850, proteinG: 70, carbsG: 70, fatG: 28, kind: 'PLATE', allergens: ['sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/congress-basel/itemid-61d2b086424b6d8fa6a6129d' },
      { id: '5ddbb2bcfb3b9dc41442905e', name: 'Chicken shawarma laffa, 185 g meat', kcal: 1000, proteinG: 50, carbsG: 90, fatG: 48, kind: 'WRAP', allergens: ['gluten', 'wheat', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/congress-basel/itemid-5ddbb2bcfb3b9dc41442905e' },
      { id: '60e475d64f6c8633215a5e8b', name: 'Chicken shawarma bowl, 200 g, with salad and tahini', kcal: 600, proteinG: 46, carbsG: 20, fatG: 36, kind: 'BOWL', allergens: ['sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/congress-basel/itemid-60e475d64f6c8633215a5e8b' },
    ],
  },
  {
    id: 'wolt-zoe-14',
    name: 'Zoe Chicken',
    lat: 32.0840213,
    lng: 34.807069,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/zoe-14',
    dishes: [
      { id: 'fcece8a8b643ee1bc088ae6d', name: 'Grilled chicken breast with two sides', kcal: 780, proteinG: 55, carbsG: 75, fatG: 26, kind: 'PLATE', allergens: [], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/zoe-14/itemid-fcece8a8b643ee1bc088ae6d' },
      { id: 'd343f174f854542bad5b7b92', name: 'Marinated chicken thigh steak with two sides', kcal: 880, proteinG: 48, carbsG: 75, fatG: 40, kind: 'PLATE', allergens: ['soy'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/zoe-14/itemid-d343f174f854542bad5b7b92' },
      { id: 'df434845f023e786f7e0b720', name: 'Giant schnitzel with two sides', kcal: 1050, proteinG: 50, carbsG: 100, fatG: 48, kind: 'PLATE', allergens: ['gluten', 'wheat', 'egg'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/zoe-14/itemid-df434845f023e786f7e0b720' },
      { id: '8efcf3d7ffdf0ff0b421f404', name: 'Chimichurri chicken breast in challah', kcal: 720, proteinG: 45, carbsG: 70, fatG: 26, kind: 'WRAP', allergens: ['gluten', 'wheat', 'egg'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/zoe-14/itemid-8efcf3d7ffdf0ff0b421f404' },
    ],
  },
  {
    id: 'wolt-shushu-malkhi-yisrael',
    name: 'Shushu',
    lat: 32.0792497,
    lng: 34.7808508,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/shushu-malkhi-yisrael',
    dishes: [
      { id: 'e40d89648817d6bd918b9e9d', name: 'Chicken couscous with vegetable soup', kcal: 820, proteinG: 45, carbsG: 105, fatG: 22, kind: 'PLATE', allergens: ['gluten', 'wheat'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/shushu-malkhi-yisrael/itemid-e40d89648817d6bd918b9e9d' },
      { id: '5672a0fb79281a3ddd5a0e8c', name: 'Couscous with beef kebab and vegetable soup', kcal: 900, proteinG: 40, carbsG: 105, fatG: 34, kind: 'PLATE', allergens: ['gluten', 'wheat'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/shushu-malkhi-yisrael/itemid-5672a0fb79281a3ddd5a0e8c' },
      { id: '61b5c8b7103b8c5561e8a2b2', name: 'Beef kebab in frena bread with tahini', kcal: 850, proteinG: 36, carbsG: 70, fatG: 46, kind: 'WRAP', allergens: ['gluten', 'wheat', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/shushu-malkhi-yisrael/itemid-61b5c8b7103b8c5561e8a2b2' },
      { id: '2f8158820a92b1ac627bbc2e', name: 'Shakshuka with warm frena bread', kcal: 650, proteinG: 24, carbsG: 70, fatG: 30, kind: 'PLATE', allergens: ['gluten', 'wheat', 'egg'], tags: ['vegetarian'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/shushu-malkhi-yisrael/itemid-2f8158820a92b1ac627bbc2e' },
    ],
  },
  {
    id: 'wolt-hummus-eliyahu-azrieli-tel-aviv',
    name: 'Hummus Eliyahu',
    lat: 32.069452,
    lng: 34.7876258,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/hummus-eliyahu-azrieli-tel-aviv',
    dishes: [
      { id: '43c9310a221c1facc1f067fa', name: 'Hummus complete: ful, tahini, chickpeas, boiled egg, pita', kcal: 820, proteinG: 32, carbsG: 90, fatG: 38, kind: 'BOWL', allergens: ['sesame', 'egg', 'gluten', 'wheat'], tags: ['vegetarian'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/hummus-eliyahu-azrieli-tel-aviv/itemid-43c9310a221c1facc1f067fa' },
      { id: 'd861bdaa2108e248afbc1445', name: 'Hummus and falafel meal with fries or salad', kcal: 1150, proteinG: 34, carbsG: 130, fatG: 55, kind: 'PLATE', allergens: ['sesame', 'gluten', 'wheat'], tags: ['vegan'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/hummus-eliyahu-azrieli-tel-aviv/itemid-d861bdaa2108e248afbc1445' },
      { id: '99c37da741de5c296adea02e', name: 'Hummus with vegan shawarma and two pitas', kcal: 900, proteinG: 38, carbsG: 100, fatG: 38, kind: 'BOWL', allergens: ['sesame', 'gluten', 'wheat', 'soy'], tags: ['vegan'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/hummus-eliyahu-azrieli-tel-aviv/itemid-99c37da741de5c296adea02e' },
      { id: '97bd5883463ec6f8c271aed3', name: 'Hummus shakshuka with pita', kcal: 780, proteinG: 30, carbsG: 85, fatG: 35, kind: 'BOWL', allergens: ['sesame', 'egg', 'gluten', 'wheat'], tags: ['vegetarian'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/hummus-eliyahu-azrieli-tel-aviv/itemid-97bd5883463ec6f8c271aed3' },
    ],
  },
  {
    id: 'wolt-yashka-dizengoff',
    name: 'Yashka',
    lat: 32.0798987,
    lng: 34.7737211,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/yashka-dizengoff',
    dishes: [
      { id: 'c1d6eb23bd6b17629756566f', name: 'Veal shawarma laffa with salads and spreads', kcal: 1000, proteinG: 46, carbsG: 90, fatG: 50, kind: 'WRAP', allergens: ['gluten', 'wheat', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/yashka-dizengoff/itemid-c1d6eb23bd6b17629756566f' },
      { id: '29a9abfc498f9c5c36b6359e', name: 'Turkey shawarma plate with salads and pita', kcal: 850, proteinG: 52, carbsG: 70, fatG: 38, kind: 'PLATE', allergens: ['gluten', 'wheat', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/yashka-dizengoff/itemid-29a9abfc498f9c5c36b6359e' },
      { id: 'c2ac5225d71e141a31c4f727', name: 'Chicken breast in pita with salads', kcal: 620, proteinG: 40, carbsG: 60, fatG: 22, kind: 'WRAP', allergens: ['gluten', 'wheat', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/yashka-dizengoff/itemid-c2ac5225d71e141a31c4f727' },
    ],
  },
  {
    id: 'wolt-meatbar-burger-ibn-gvirol',
    name: 'MeatBar Burger',
    lat: 32.0792696,
    lng: 34.7811299,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/meatbar-burger-ibn-gvirol',
    dishes: [
      { id: '778770552b1dfd569181a029', name: 'Burger, 200 g, with spicy mayo', kcal: 720, proteinG: 40, carbsG: 45, fatG: 42, kind: 'PLATE', allergens: ['gluten', 'wheat', 'egg', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/meatbar-burger-ibn-gvirol/itemid-778770552b1dfd569181a029' },
      { id: 'c47d905a01d216ce5d7bb989', name: 'Cheeseburger, 200 g, with Belgian fries', kcal: 1250, proteinG: 50, carbsG: 105, fatG: 68, kind: 'PLATE', allergens: ['gluten', 'wheat', 'egg', 'dairy', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/meatbar-burger-ibn-gvirol/itemid-c47d905a01d216ce5d7bb989' },
      { id: 'f04687a0f6e553c321353c72', name: 'Double burger, 400 g', kcal: 1150, proteinG: 76, carbsG: 45, fatG: 74, kind: 'PLATE', allergens: ['gluten', 'wheat', 'egg', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/meatbar-burger-ibn-gvirol/itemid-f04687a0f6e553c321353c72' },
      { id: '19305e3a2bdb00297182696a', name: 'Vegan Redefine burger with fries', kcal: 1050, proteinG: 30, carbsG: 100, fatG: 58, kind: 'PLATE', allergens: ['gluten', 'wheat', 'soy'], tags: ['vegan'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/meatbar-burger-ibn-gvirol/itemid-19305e3a2bdb00297182696a' },
    ],
  },
  {
    id: 'wolt-hamosad',
    name: 'HaMosad',
    lat: 32.0792696,
    lng: 34.7811299,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/hamosad',
    dishes: [
      { id: 'b14178df3e86843398570269', name: 'Double smashburger with arugula', kcal: 820, proteinG: 44, carbsG: 45, fatG: 50, kind: 'PLATE', allergens: ['gluten', 'wheat', 'egg', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/hamosad/itemid-b14178df3e86843398570269' },
      { id: '64a4102c970321e228efae76', name: 'Crispy chicken sandwich with a side and a drink', kcal: 1200, proteinG: 42, carbsG: 140, fatG: 50, kind: 'PLATE', allergens: ['gluten', 'wheat', 'egg'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/hamosad/itemid-64a4102c970321e228efae76' },
      { id: 'd52acdb09af2f3b18ea995a2', name: 'HaMosad cheeseburger with house aioli', kcal: 780, proteinG: 42, carbsG: 45, fatG: 46, kind: 'PLATE', allergens: ['gluten', 'wheat', 'egg', 'dairy', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/hamosad/itemid-d52acdb09af2f3b18ea995a2' },
    ],
  },
  {
    id: 'wolt-nam-king-george',
    name: 'Nam',
    lat: 32.07720107,
    lng: 34.77768302,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/nam-king-george',
    dishes: [
      { id: 'c3c45eb399fe7a6fc9cba584', name: 'Pad thai with egg and peanuts', kcal: 820, proteinG: 28, carbsG: 105, fatG: 30, kind: 'BOWL', allergens: ['egg', 'peanut', 'fish', 'soy'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/nam-king-george/itemid-c3c45eb399fe7a6fc9cba584' },
      { id: '25ab6d77409eba91a789b38a', name: 'Pad kra pao with rice and an omelette', kcal: 780, proteinG: 38, carbsG: 85, fatG: 30, kind: 'BOWL', allergens: ['egg', 'gluten', 'wheat', 'soy', 'shellfish'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/nam-king-george/itemid-25ab6d77409eba91a789b38a' },
      { id: 'cbe507c57e02fa2b52831e02', name: 'Massaman curry with potato, peanuts and rice', kcal: 900, proteinG: 32, carbsG: 95, fatG: 42, kind: 'BOWL', allergens: ['peanut', 'fish'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/nam-king-george/itemid-cbe507c57e02fa2b52831e02' },
      { id: 'bd9357f1ae4898f332139871', name: 'Crispy chicken thigh in plum sauce with rice', kcal: 820, proteinG: 36, carbsG: 105, fatG: 26, kind: 'BOWL', allergens: ['gluten', 'wheat', 'soy'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/nam-king-george/itemid-bd9357f1ae4898f332139871' },
    ],
  },
  {
    id: 'wolt-giraffe-ibn-gabirol',
    name: 'Giraffe',
    lat: 32.071644,
    lng: 34.785075,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/giraffe-ibn-gabirol',
    dishes: [
      { id: 'aeccb390f437bd7c2e26c5a5', name: 'Sirloin noodles with cashews and three onions', kcal: 850, proteinG: 38, carbsG: 95, fatG: 32, kind: 'BOWL', allergens: ['gluten', 'wheat', 'egg', 'soy', 'tree_nut'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/giraffe-ibn-gabirol/itemid-aeccb390f437bd7c2e26c5a5' },
      { id: '90cd197c040c298ac14ffa01', name: 'Beef rice noodles with broccoli', kcal: 780, proteinG: 36, carbsG: 100, fatG: 24, kind: 'BOWL', allergens: ['soy', 'gluten', 'wheat'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/giraffe-ibn-gabirol/itemid-90cd197c040c298ac14ffa01' },
      { id: '548ef70a3be0a90e028a1d54', name: 'Teriyaki chicken noodles, small', kcal: 520, proteinG: 26, carbsG: 70, fatG: 14, kind: 'BOWL', allergens: ['gluten', 'wheat', 'egg', 'soy'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/giraffe-ibn-gabirol/itemid-548ef70a3be0a90e028a1d54' },
      { id: '546b1ee6b192e0a59bb2c471', name: 'Miso caesar salad with grilled chicken and avocado', kcal: 560, proteinG: 40, carbsG: 22, fatG: 34, kind: 'BOWL', allergens: ['soy', 'egg', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/giraffe-ibn-gabirol/itemid-546b1ee6b192e0a59bb2c471' },
    ],
  },
  {
    id: 'wolt-nini-hachi',
    name: 'Nini Hachi',
    lat: 32.0919271,
    lng: 34.7747913,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/nini-hachi',
    dishes: [
      { id: '7e0ff73b79e2fbff5b6889b3', name: 'Pad thai with tofu, egg and peanuts', kcal: 720, proteinG: 24, carbsG: 95, fatG: 26, kind: 'BOWL', allergens: ['egg', 'peanut', 'soy', 'fish'], tags: ['vegetarian'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/nini-hachi/itemid-7e0ff73b79e2fbff5b6889b3' },
      { id: 'a250e92a2da671e13cf5475c', name: 'Chopped salmon poke with avocado and edamame', kcal: 680, proteinG: 32, carbsG: 80, fatG: 24, kind: 'BOWL', allergens: ['fish', 'soy', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/nini-hachi/itemid-a250e92a2da671e13cf5475c' },
      { id: '440b49b3d84e93a128fba4dc', name: 'Pad see ew with mushrooms and egg', kcal: 700, proteinG: 20, carbsG: 100, fatG: 22, kind: 'BOWL', allergens: ['egg', 'soy', 'gluten', 'wheat'], tags: ['vegetarian'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/nini-hachi/itemid-440b49b3d84e93a128fba4dc' },
    ],
  },
  {
    id: 'wolt-pasta-e-via',
    name: 'Pasta Via',
    lat: 32.08880487,
    lng: 34.78267193,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/pasta-e-via',
    dishes: [
      { id: '66d431369031cbb601f8a27d', name: 'Bolognese with beef braised in red wine', kcal: 850, proteinG: 38, carbsG: 100, fatG: 30, kind: 'PLATE', allergens: ['gluten', 'wheat'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/pasta-e-via/itemid-66d431369031cbb601f8a27d' },
      { id: '70eea73a240918afa7e42003', name: 'Pollo al limone: chicken pasta with butter, garlic and parmesan', kcal: 900, proteinG: 45, carbsG: 95, fatG: 36, kind: 'PLATE', allergens: ['gluten', 'wheat', 'dairy'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/pasta-e-via/itemid-70eea73a240918afa7e42003' },
      { id: '5d270a44376d8594c9acedf9', name: 'Meat and cheese lasagna', kcal: 880, proteinG: 42, carbsG: 70, fatG: 46, kind: 'PLATE', allergens: ['gluten', 'wheat', 'dairy', 'egg'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/pasta-e-via/itemid-5d270a44376d8594c9acedf9' },
      { id: '035dfd7c22382f4c9ac9c968', name: 'Cacio e pepe linguine', kcal: 820, proteinG: 30, carbsG: 100, fatG: 32, kind: 'PLATE', allergens: ['gluten', 'wheat', 'dairy'], tags: ['vegetarian'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/pasta-e-via/itemid-035dfd7c22382f4c9ac9c968' },
    ],
  },
  {
    id: 'wolt-taqueria-1',
    name: 'Taqueria',
    lat: 32.06242193,
    lng: 34.79052171,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/taqueria-1',
    dishes: [
      { id: 'a2c275f7b9696a971f25e041', name: 'Steak burrito with rice, beans and sour cream', kcal: 950, proteinG: 45, carbsG: 105, fatG: 36, kind: 'WRAP', allergens: ['gluten', 'wheat', 'dairy'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/taqueria-1/itemid-a2c275f7b9696a971f25e041' },
      { id: '5835ee557bd5891cde3c9234', name: 'Chipotle chicken burrito with rice and beans', kcal: 900, proteinG: 46, carbsG: 105, fatG: 30, kind: 'WRAP', allergens: ['gluten', 'wheat', 'dairy'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/taqueria-1/itemid-5835ee557bd5891cde3c9234' },
      { id: '17ee4d359349ea738971101c', name: 'Steak burrito bowl, no tortilla', kcal: 720, proteinG: 42, carbsG: 75, fatG: 28, kind: 'BOWL', allergens: ['dairy'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/taqueria-1/itemid-17ee4d359349ea738971101c' },
      { id: 'e706ccda50ae4ab89f0cd090', name: 'Pulled beef quesadilla', kcal: 560, proteinG: 30, carbsG: 40, fatG: 30, kind: 'WRAP', allergens: ['gluten', 'wheat', 'dairy'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/taqueria-1/itemid-e706ccda50ae4ab89f0cd090' },
    ],
  },
  {
    id: 'wolt-benedict-sarona',
    name: 'Benedict',
    lat: 32.071572,
    lng: 34.78654,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/benedict-sarona',
    dishes: [
      { id: '8baf494df8def6deaba86c19', name: 'Full English breakfast', kcal: 1100, proteinG: 45, carbsG: 70, fatG: 70, kind: 'PLATE', allergens: ['gluten', 'wheat', 'egg'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/benedict-sarona/itemid-8baf494df8def6deaba86c19' },
      { id: 'a0f1b74a1016290fbcd3bdb7', name: 'Shakshuka with challah, tahini and salad', kcal: 850, proteinG: 30, carbsG: 85, fatG: 42, kind: 'PLATE', allergens: ['gluten', 'wheat', 'egg', 'sesame'], tags: ['vegetarian'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/benedict-sarona/itemid-a0f1b74a1016290fbcd3bdb7' },
      { id: '0c90ba945b06af59f8adff75', name: 'Smoked salmon bagel with scrambled eggs and cream cheese', kcal: 750, proteinG: 38, carbsG: 65, fatG: 36, kind: 'WRAP', allergens: ['gluten', 'wheat', 'egg', 'dairy', 'fish', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/benedict-sarona/itemid-0c90ba945b06af59f8adff75' },
      { id: '4194afeae22ee7ed4dff3b1b', name: 'Philly cheesesteak on ciabatta', kcal: 950, proteinG: 50, carbsG: 75, fatG: 48, kind: 'WRAP', allergens: ['gluten', 'wheat', 'dairy', 'egg'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/benedict-sarona/itemid-4194afeae22ee7ed4dff3b1b' },
      { id: '930ae81ead32e0f916f8161e', name: 'Cheddar pancakes with bacon and a fried egg', kcal: 900, proteinG: 32, carbsG: 95, fatG: 42, kind: 'PLATE', allergens: ['gluten', 'wheat', 'egg', 'dairy'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/benedict-sarona/itemid-930ae81ead32e0f916f8161e' },
    ],
  },
  {
    id: 'wolt-shake-house',
    name: 'Shake House',
    lat: 32.08459157,
    lng: 34.81312789,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/shake-house',
    dishes: [
      { id: '960bdffa81aba13ee1b1c48c', name: 'Fruit shake, build your own', kcal: 420, proteinG: 8, carbsG: 90, fatG: 4, kind: 'DRINK', allergens: [], tags: ['vegan'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/shake-house/itemid-960bdffa81aba13ee1b1c48c' },
      { id: 'a33ea09780bd983be6f516e1', name: 'Frozen yogurt bowl with fruit and toppings', kcal: 560, proteinG: 14, carbsG: 95, fatG: 14, kind: 'BOWL', allergens: ['dairy'], tags: ['vegetarian'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/shake-house/itemid-a33ea09780bd983be6f516e1' },
    ],
  },
  {
    id: 'wolt-denita-shake',
    name: 'Denita Shake',
    lat: 32.0823386,
    lng: 34.7814705,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/denita-shake',
    dishes: [
      { id: '61965db27f7497b36ee11cbc', name: 'Chocolate shake: banana, dates, peanut butter, oats, cocoa', kcal: 620, proteinG: 16, carbsG: 95, fatG: 20, kind: 'DRINK', allergens: ['peanut', 'gluten'], tags: ['vegan'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/denita-shake/itemid-61965db27f7497b36ee11cbc' },
      { id: '05040d4cb0cec4c0a431e0ce', name: 'Chocolate protein shake with banana and almond milk', kcal: 380, proteinG: 30, carbsG: 45, fatG: 8, kind: 'DRINK', allergens: ['tree_nut', 'dairy'], tags: ['vegetarian'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/denita-shake/itemid-05040d4cb0cec4c0a431e0ce' },
      { id: '14c717f5facb9b1f79191a8e', name: 'Banana protein shake with almond milk', kcal: 370, proteinG: 30, carbsG: 45, fatG: 7, kind: 'DRINK', allergens: ['tree_nut', 'dairy'], tags: ['vegetarian'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/denita-shake/itemid-14c717f5facb9b1f79191a8e' },
      { id: '619669e5f497d2f4de07362e', name: 'Bologna shake: banana, dates, tahini, silan, pecans', kcal: 560, proteinG: 10, carbsG: 80, fatG: 22, kind: 'DRINK', allergens: ['sesame', 'tree_nut'], tags: ['vegan'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/denita-shake/itemid-619669e5f497d2f4de07362e' },
      { id: 'd4ae636db9283efab7b283aa', name: 'Oat bowl in almond milk with toppings', kcal: 550, proteinG: 14, carbsG: 85, fatG: 16, kind: 'BOWL', allergens: ['gluten', 'tree_nut'], tags: ['vegan'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/denita-shake/itemid-d4ae636db9283efab7b283aa' },
    ],
  },
  {
    id: 'wolt-under-the-tree',
    name: 'Under The Tree',
    lat: 32.09026376,
    lng: 34.77417469,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/under-the-tree',
    dishes: [
      { id: '0233476659e9e44e4b5c797b', name: 'Chipotle chicken rice with avocado salad', kcal: 680, proteinG: 40, carbsG: 75, fatG: 22, kind: 'BOWL', allergens: [], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/under-the-tree/itemid-0233476659e9e44e4b5c797b' },
      { id: '886d3343fa54c52db5702516', name: 'Shawarma bowl on rice or freekeh', kcal: 720, proteinG: 40, carbsG: 75, fatG: 28, kind: 'BOWL', allergens: ['sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/under-the-tree/itemid-886d3343fa54c52db5702516' },
      { id: 'ffd9c220afd2866672cb9bf8', name: 'Slow-roasted asado with rice, black beans and broccoli (40 g protein)', kcal: 780, proteinG: 40, carbsG: 75, fatG: 34, kind: 'BOWL', allergens: [], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/under-the-tree/itemid-ffd9c220afd2866672cb9bf8' },
      { id: 'a9b6a7c5d93e9e1376afe728', name: 'Indian tomato curry chicken with rice and almonds', kcal: 700, proteinG: 38, carbsG: 75, fatG: 26, kind: 'BOWL', allergens: ['tree_nut'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/under-the-tree/itemid-a9b6a7c5d93e9e1376afe728' },
      { id: '09b503b0515b7b20a57bcba9', name: 'Roast chicken salad (50 g protein)', kcal: 480, proteinG: 50, carbsG: 15, fatG: 24, kind: 'BOWL', allergens: ['sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/under-the-tree/itemid-09b503b0515b7b20a57bcba9' },
    ],
  },
  {
    id: 'wolt-itzik-and-ruti',
    name: 'Itzik and Ruti',
    lat: 32.0796232,
    lng: 34.7733584,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/itzik-and-ruti',
    dishes: [
      { id: '668f9a9097d10b1166e0ce3f', name: 'Schnitzel in challah with salads', kcal: 950, proteinG: 42, carbsG: 100, fatG: 40, kind: 'WRAP', allergens: ['gluten', 'wheat', 'egg', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/itzik-and-ruti/itemid-668f9a9097d10b1166e0ce3f' },
      { id: '34ce88684168468996673880', name: 'Schnitzel and egg salad sandwich', kcal: 1000, proteinG: 46, carbsG: 95, fatG: 48, kind: 'WRAP', allergens: ['gluten', 'wheat', 'egg'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/itzik-and-ruti/itemid-34ce88684168468996673880' },
      { id: '64d4d77c0b647e95ad3fd227', name: "Chef's sandwich: scrambled eggs and smoked sausage", kcal: 800, proteinG: 34, carbsG: 70, fatG: 40, kind: 'WRAP', allergens: ['gluten', 'wheat', 'egg'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/itzik-and-ruti/itemid-64d4d77c0b647e95ad3fd227' },
      { id: '65718745f2cb36e0f001ff8d', name: 'Tuna and spicy carrot sandwich', kcal: 650, proteinG: 32, carbsG: 70, fatG: 24, kind: 'WRAP', allergens: ['gluten', 'wheat', 'fish', 'egg'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/itzik-and-ruti/itemid-65718745f2cb36e0f001ff8d' },
    ],
  },
  {
    id: 'wolt-market-seasonal-kitchen',
    name: 'Market Vegan',
    lat: 32.08242365,
    lng: 34.77402449,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/market-seasonal-kitchen',
    dishes: [
      { id: '5c97f3cd1d9a4f8797ec4ca0', name: 'Tofu shawarma bowl with roasted mushrooms and tahini', kcal: 680, proteinG: 30, carbsG: 75, fatG: 28, kind: 'BOWL', allergens: ['soy', 'sesame'], tags: ['vegan'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/market-seasonal-kitchen/itemid-5c97f3cd1d9a4f8797ec4ca0' },
      { id: 'f7e770a42a49651d931e0229', name: 'Vegan kebab bowl on rice or quinoa', kcal: 700, proteinG: 28, carbsG: 80, fatG: 28, kind: 'BOWL', allergens: ['soy', 'sesame'], tags: ['vegan'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/market-seasonal-kitchen/itemid-f7e770a42a49651d931e0229' },
      { id: '5bfed8c5576bda000adc50d8', name: 'Indian lentil curry with rice and coconut cream', kcal: 640, proteinG: 22, carbsG: 95, fatG: 18, kind: 'BOWL', allergens: [], tags: ['vegan'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/market-seasonal-kitchen/itemid-5bfed8c5576bda000adc50d8' },
      { id: '5dc19bf52427aaeb0ddd6c32', name: 'Tex-Mex bean and sweet potato stew', kcal: 620, proteinG: 20, carbsG: 100, fatG: 14, kind: 'BOWL', allergens: [], tags: ['vegan'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/market-seasonal-kitchen/itemid-5dc19bf52427aaeb0ddd6c32' },
    ],
  },
  {
    id: 'wolt-papi-pizza',
    name: 'Papi Pizza',
    lat: 32.0804467,
    lng: 34.7815883,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/papi-pizza',
    dishes: [
      { id: '4239f31ea47d52bef3b49cf7', name: 'Garlic confit focaccia with mozzarella', kcal: 780, proteinG: 26, carbsG: 95, fatG: 32, kind: 'PLATE', allergens: ['gluten', 'wheat', 'dairy'], tags: ['vegetarian'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/papi-pizza/itemid-4239f31ea47d52bef3b49cf7' },
    ],
  },
  {
    id: 'wolt-wok-republic-london-ministore',
    name: 'Wok Republic',
    lat: 32.075552,
    lng: 34.782584,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/wok-republic-london-ministore',
    dishes: [
      { id: '28ec4521712e2c05647687b1', name: 'Chicken satay noodles with peanut sauce', kcal: 850, proteinG: 36, carbsG: 95, fatG: 34, kind: 'BOWL', allergens: ['gluten', 'wheat', 'egg', 'peanut', 'soy'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/wok-republic-london-ministore/itemid-28ec4521712e2c05647687b1' },
      { id: '1681e288321daadfa600da1e', name: "General Tso's chicken with steamed rice", kcal: 900, proteinG: 34, carbsG: 120, fatG: 28, kind: 'BOWL', allergens: ['gluten', 'wheat', 'egg', 'soy'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/wok-republic-london-ministore/itemid-1681e288321daadfa600da1e' },
      { id: 'f850d41a17c9ef74f082cfb5', name: 'Fried rice with egg and chicken', kcal: 780, proteinG: 32, carbsG: 100, fatG: 26, kind: 'BOWL', allergens: ['egg', 'soy', 'gluten', 'wheat'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/wok-republic-london-ministore/itemid-f850d41a17c9ef74f082cfb5' },
      { id: 'd3741dc3f9e97b97efc78338', name: 'Beef rice noodles with green beans', kcal: 760, proteinG: 34, carbsG: 100, fatG: 22, kind: 'BOWL', allergens: ['soy', 'gluten', 'wheat'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/wok-republic-london-ministore/itemid-d3741dc3f9e97b97efc78338' },
    ],
  },
  {
    id: 'wolt-cafe-noir',
    name: 'Café Noir',
    lat: 32.06564588843655,
    lng: 34.775604206310504,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/cafe-noir',
    dishes: [
      { id: '6477382f2ecad11c9dca63e4', name: 'Chicken schnitzel with a side', kcal: 950, proteinG: 50, carbsG: 80, fatG: 46, kind: 'PLATE', allergens: ['gluten', 'wheat', 'egg'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/cafe-noir/itemid-6477382f2ecad11c9dca63e4' },
      { id: '63aa95b419d27f3eb2925766', name: 'Seared salmon fillet with greens and a side', kcal: 820, proteinG: 46, carbsG: 50, fatG: 46, kind: 'PLATE', allergens: ['fish'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/cafe-noir/itemid-63aa95b419d27f3eb2925766' },
      { id: '63aa95b419d27f3eb292576a', name: 'Grilled chicken thighs on Druze pita with a side', kcal: 950, proteinG: 50, carbsG: 80, fatG: 46, kind: 'PLATE', allergens: ['gluten', 'wheat'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/cafe-noir/itemid-63aa95b419d27f3eb292576a' },
      { id: '653902bc52fd17a263145131', name: 'Pulled asado sandwich with chipotle sauce', kcal: 850, proteinG: 42, carbsG: 65, fatG: 46, kind: 'WRAP', allergens: ['gluten', 'wheat', 'egg'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/cafe-noir/itemid-653902bc52fd17a263145131' },
    ],
  },
  {
    id: 'wolt-torta-loca',
    name: 'HaMexicani',
    lat: 32.077513,
    lng: 34.79327,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/torta-loca',
    dishes: [
      { id: '181b50386ddd56487988945e', name: 'Entrecôte tortilla wrap with salads and sauces', kcal: 950, proteinG: 45, carbsG: 80, fatG: 48, kind: 'WRAP', allergens: ['gluten', 'wheat', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/torta-loca/itemid-181b50386ddd56487988945e' },
      { id: '364dc1c856579af694ca237a', name: 'Chicken breast tortilla wrap with salads and sauces', kcal: 800, proteinG: 50, carbsG: 80, fatG: 28, kind: 'WRAP', allergens: ['gluten', 'wheat', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/torta-loca/itemid-364dc1c856579af694ca237a' },
      { id: '83fdb4a89f1b627da8c12d1c', name: 'HaMexicani wrap: ground beef and entrecôte', kcal: 1000, proteinG: 46, carbsG: 80, fatG: 54, kind: 'WRAP', allergens: ['gluten', 'wheat', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/torta-loca/itemid-83fdb4a89f1b627da8c12d1c' },
    ],
  },
  {
    id: 'wolt-shi-shi',
    name: 'Shi-Shi',
    lat: 32.075443,
    lng: 34.7815,
    woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/shi-shi',
    dishes: [
      { id: 'f49cc279211b745178d8b789', name: 'Crispy Chick: panko chicken breast rice bowl', kcal: 820, proteinG: 42, carbsG: 95, fatG: 28, kind: 'BOWL', allergens: ['gluten', 'wheat', 'egg', 'soy', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/shi-shi/itemid-f49cc279211b745178d8b789' },
      { id: '243697c11de83a9e813034bd', name: 'Tuna and salmon tartare rice bowl', kcal: 680, proteinG: 36, carbsG: 85, fatG: 20, kind: 'BOWL', allergens: ['fish', 'soy', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/shi-shi/itemid-243697c11de83a9e813034bd' },
      { id: '3843ffdf6b6e62dc4c7ebad0', name: 'Orange chicken with rice', kcal: 880, proteinG: 36, carbsG: 115, fatG: 28, kind: 'BOWL', allergens: ['gluten', 'wheat', 'egg', 'soy'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/shi-shi/itemid-3843ffdf6b6e62dc4c7ebad0' },
      { id: '7f4586cffd942f99bdf931e4', name: 'Queen Salmon: baked salmon bowl with Asian vinaigrette', kcal: 700, proteinG: 36, carbsG: 80, fatG: 24, kind: 'BOWL', allergens: ['fish', 'soy', 'sesame'], woltUrl: 'https://wolt.com/en/isr/tel-aviv/restaurant/shi-shi/itemid-7f4586cffd942f99bdf931e4' },
    ],
  },
];

/** Everywhere we cover: central Tel Aviv, then the rest of Israel (nearbyVenuesIsrael.ts). */
export const NEARBY_VENUES: NearbyVenue[] = [...CENTRAL_TEL_AVIV_VENUES, ...ISRAEL_VENUES];

/**
 * Made-up places for trying the screen (NEARBY_SAMPLE_VENUES=true). They're
 * placed around wherever the user is, and have no Wolt links.
 */
export function sampleVenues(lat: number, lng: number): NearbyVenue[] {
  const at = (dLat: number, dLng: number) => ({ lat: lat + dLat, lng: lng + dLng });
  return [
    {
      id: 'sample-grain-grill',
      name: 'Grain & Grill',
      ...at(0.006, 0.003),
      woltUrl: null,
      dishes: [
        { id: 'gg-shawarma', name: 'Chicken shawarma bowl', kcal: 690, proteinG: 48, carbsG: 62, fatG: 24, kind: 'BOWL', allergens: ['sesame'], woltUrl: null },
        { id: 'gg-falafel', name: 'Falafel bowl with tahini', kcal: 640, proteinG: 22, carbsG: 70, fatG: 28, kind: 'BOWL', allergens: ['sesame'], tags: ['vegan'], woltUrl: null },
      ],
    },
    {
      id: 'sample-lavash-lane',
      name: 'Lavash Lane',
      ...at(-0.008, 0.005),
      woltUrl: null,
      dishes: [
        { id: 'll-halloumi', name: 'Halloumi and egg wrap', kcal: 610, proteinG: 32, carbsG: 48, fatG: 30, kind: 'WRAP', allergens: ['dairy', 'egg', 'gluten', 'wheat'], woltUrl: null },
        { id: 'll-steak', name: 'Steak wrap', kcal: 720, proteinG: 44, carbsG: 52, fatG: 32, kind: 'WRAP', allergens: ['gluten', 'wheat'], woltUrl: null },
      ],
    },
    {
      id: 'sample-peak-smoothies',
      name: 'Peak Smoothies',
      ...at(0.003, -0.004),
      woltUrl: null,
      dishes: [
        { id: 'ps-pb-shake', name: 'Peanut butter banana oat shake', kcal: 520, proteinG: 34, carbsG: 60, fatG: 16, kind: 'DRINK', allergens: ['peanut', 'dairy'], woltUrl: null },
        { id: 'ps-berry', name: 'Berry protein smoothie', kcal: 430, proteinG: 30, carbsG: 58, fatG: 8, kind: 'DRINK', allergens: ['dairy'], woltUrl: null },
      ],
    },
    {
      id: 'sample-pasta-corner',
      name: 'Pasta Corner',
      ...at(-0.012, -0.007),
      woltUrl: null,
      dishes: [
        { id: 'pc-pesto', name: 'Chicken pesto pasta', kcal: 760, proteinG: 44, carbsG: 80, fatG: 26, kind: 'PLATE', allergens: ['gluten', 'wheat', 'dairy', 'tree_nut'], woltUrl: null },
        { id: 'pc-tomato', name: 'Tomato pasta with meatballs', kcal: 700, proteinG: 38, carbsG: 84, fatG: 22, kind: 'PLATE', allergens: ['gluten', 'wheat'], woltUrl: null },
      ],
    },
  ];
}
