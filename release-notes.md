---
layout: default
title: Release Notes
---

# Release Notes

{% include platform-toggle.html %}

## 1.1.2 — Unreleased

Common changes:

- **Foldable and wide screens**
  - Supports iPhone Duo on iOS and Galaxy Fold and tablets on Android. Phone layouts are unchanged.
  - On a wide screen the shooting page uses the extra room: a wider single column, or inputs and results side by side.
  - When the device is half open, the page, page dots and timers stay clear of the fold.
  - Running timers can sit in a column beside the page: up to three cards, with View all for the rest.
  - Folding, unfolding and rotating keep your open screens and edits.

<div class="gallery fold">
{% include shot.html name="rn-1.1.2-book" alt="Shooting screen half open like a book, with results on the other side of the fold" caption="Half open like a book" %}
{% include shot.html name="rn-1.1.2-tabletop" alt="Shooting screen half open on a table, with results above the fold" caption="Half open on a table" %}
{% include shot.html name="rn-1.1.2-outer" alt="Shooting screen on the outer display with timers in a side column" caption="Folded, on the outer display" %}
</div>

## 1.0.1

This release includes the changes beta-tested in 0.9.1, documented below.

Common changes:

- **Your own camera list**
  - No more four-camera limit: add as many cameras as you use, and give each one its own name.
  - Each camera remembers its own film, base shutter, filters, and target shutter.
  - Reorder, hide, or delete cameras. Hidden cameras keep their settings.

<div class="gallery">
{% include shot.html name="home-shooting-503" alt="Shooting screen in 1.0" caption="The 1.0 shooting screen" %}
{% include shot.html name="rn-1.0.0-camera-list" alt="Camera list with five named cameras" caption="Your camera list" %}
</div>

## 0.9.1 — Beta tested; included in 1.0.1

Retained here as beta testing history. These changes were released together in 1.0.1.

Common changes:

- **Filter Sets**
  - Create named Filter Sets for the physical filters you own, such as 2-, 3-, 6-, and 10-stop ND filters.
  - Add CPL, GND, color filters such as red, orange, and yellow, and effect filters to a set.
  - Select only the sets relevant to each camera, so its filter choices reflect the equipment you have with you.
  - Choose ND filters directly from a selected Filter Set, and keep each camera's selected sets and filter setup when you return to the app.
  - Keep standard ND filters from 1 to 30 stops available for common values.
  - Start with example Filter Sets, then edit them to match your equipment.

<div class="gallery">
{% include shot.html name="home-filters" alt="Shooting filters from two Filter Sets" caption="Choose filters from your Filter Sets" %}
</div>

Android:

- Keep the main shooting screen, mini timer, timer list, and reciprocity details readable across system font sizes.

## 0.8.0

Common changes:

- Stack up to four standard filters for exposure calculations.
- Added accurate fractional-stop support for ND100, ND200, and ND100k filters.
- Improved the reliability of saved data, timer restoration, and overall app behavior.

<div class="gallery">
{% include shot.html name="rn-0.8.0-filter-stack" alt="Two stacked ND filters, ND200 and 3 stops, in 0.8.0" caption="Stacked standard filters" %}
</div>

Android:

- Fixed a crash that could occur when reopening the app with a running timer.
- Improved camera-slot handling, state restoration, touch targets, localization, and overall stability.

## 0.7.4 (Initial release)

- ND filter exposure calculation
- Film reciprocity correction with verified official data for film stocks from ILFORD, Kodak, Fujifilm, Rollei, and other manufacturers
- Target shutter support
- Multi-camera shooting timers
- VoiceOver (iOS) and TalkBack (Android) accessibility support

<div class="gallery">
{% include shot.html name="rn-0.7.4-shooting" alt="Shooting screen in 0.7.4" caption="Exposure with film reciprocity correction" %}
{% include shot.html name="rn-0.7.4-reciprocity" alt="Reciprocity details in 0.7.4" caption="Reciprocity details" %}
{% include shot.html name="rn-0.7.4-custom-film" alt="New custom film in 0.7.4" caption="Your own custom film" %}
</div>
