# Cuppa App - Design System Guide ☕✨
This guide contains all the visual properties used in the Cuppa application. You can use this to easily recreate the UI in Figma or include it in your graduation project presentation.

## 1. Typography (Google Fonts)
The app uses a modern combination of a serif font for elegant headings and a sans-serif font for clean, readable body text.

### **Primary Font: Playfair Display**
*Used for: Headings, App Bar Titles, Featured Drink Names, Profile Name.*
- **Weights:** Regular (400), SemiBold (600), Bold (700).
- **Colors:** Usually `Espresso` or `White` (on dark backgrounds).

### **Secondary Font: Inter**
*Used for: Body text, buttons, descriptions, prices, navigation labels.*
- **Weights:** Regular (400), Medium (500), SemiBold (600).
- **Sizes:** 
  - Body: `14px` - `16px`
  - Small text (tags, points): `11px` - `12px`

---

## 2. Color Palette
Here are the exact Hex codes used in the app's `AppColors` file.

### Primary Coffee Palette
- **Espresso (Main Dark):** `#2C1810` (Used for primary text and deep backgrounds)
- **Dark Roast:** `#4A2C2A` (Used for App Bars, primary buttons)
- **Mocha:** `#6B3F35` (Used for secondary elements, gradient stops)
- **Caramel (Brand Accent):** `#B87333` (Used for active icons, switches, highlights)
- **Latte:** `#D4956A`
- **Cream:** `#F5E6D3` (Used for light backgrounds on icons, unselected states)
- **Foam:** `#FFFBF7`
- **Warm White (Scaffold Background):** `#FAF3EB` (The main background color of the app)

### Accent & Feedback Colors
- **Gold (Rewards & Premium):** `#D4A853` (Used for stars, loyalty points, gold member tags)
- **Soft Gray:** `#8B7355` (Used for subtitles, inactive text, hints)
- **Error Red:** `#D45B4A`
- **Success Green:** `#5B8A6B`

---

## 3. Gradients
Gradients are a core part of the premium feel of Cuppa.

- **Splash/Hero Gradient:**
  - Direction: Top Left to Bottom Right
  - Colors: `#2C1810` ➔ `#6B3F35` ➔ `#B87333`
- **Button Gradient:**
  - Direction: Center Left to Center Right
  - Colors: `#4A2C2A` ➔ `#6B3F35`
- **Card Gradient:**
  - Direction: Top Left to Bottom Right
  - Colors: `#4A2C2A` ➔ `#2C1810`

---

## 4. UI Components & Spacing

### Buttons
- **Border Radius:** `16px` (Fully rounded rectangle)
- **Height:** `56px`
- **Shadow:** Mild shadow, `Blur: 10px`, `Opacity: 20%`, `Offset: (0, 4)`

### Cards (Featured Drinks, Menu Items)
- **Border Radius:** `20px` to `24px`
- **Background:** White (`#FFFFFF`) or Warm Gradient for premium items.
- **Shadow:** `Blur: 15px`, `Opacity: 4%`, `Color: Black`

### Text Fields (Inputs)
- **Border Radius:** `14px`
- **Background:** White (`#FFFFFF`)
- **Border:** `1.5px` solid `#F5E6D3` (Cream)
- **Focused Border:** `2px` solid `#B87333` (Caramel)

### Padding & Margins
- **Screen Padding (Edges):** `20px` or `24px`
- **Spacing between list items:** `16px`

---
*Tip for Figma:* Create these colors as "Local Styles" and the fonts as "Text Styles" before you start dropping your screenshots into the frames!
