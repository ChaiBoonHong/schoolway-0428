# Lexend Font Installation Guide

This directory should contain the Lexend font files for the SchoolWay application.

## Required Font Files

You need to download and place the following Lexend font files in this directory (`assets/fonts/`):

- `Lexend-Regular.ttf`
- `Lexend-SemiBold.ttf`
- `Lexend-Bold.ttf`

## How to Download Lexend Fonts

### Method 1: Google Fonts (Recommended)

1. Visit [Google Fonts - Lexend](https://fonts.google.com/specimen/Lexend)
2. Click the "Download family" button (top right)
3. Extract the downloaded ZIP file
4. Copy the following files from the `static` folder to this `assets/fonts` directory:
   - `Lexend-Regular.ttf`
   - `Lexend-SemiBold.ttf`
   - `Lexend-Bold.ttf`

### Method 2: Direct Download

You can also download the font directly from the [Lexend GitHub repository](https://github.com/googlefonts/lexend/tree/main/fonts/ttf).

## After Installation

1. Ensure all three font files are in the `assets/fonts/` directory
2. Run `flutter pub get` to update dependencies
3. Restart your Flutter application

## Verify Installation

If the fonts are properly installed, all text in the SchoolWay app will display using the Lexend font family.

