# Code Style

These rules apply across the Studentos project.

## General Rules

- Do not use emoji in code, documentation, or comments.
- Keep comments minimal.
- Do not add comments for obvious code.
- Prefer clear naming and small functions over explanatory comments.

## Commenting Rules

- Use Doxygen-style comments for a function, class, or module
- Have comments for non-trivial behavior that needs to be documented for future readers.
- If logic is complex, add a comment that explains both what the logic does and why it exists.
- If logic is simple or self-explanatory, do not add comments.
- Avoid filler comments that repeat the code.

## Practical Guidance

- Comment only when the reasoning would not be obvious from the code itself.
- When you do comment, make the comment useful for maintenance, not decoration.
- Keep the style consistent across feature modules and shared utilities.

## UI Styling Guidelines -- Maybe Maybe Not

The user interface should follow Amazon's design language and patterns used across their apps:

- **Color Palette**: Use Amazon's primary blue (#FF9900 for accents, with neutral grays for backgrounds) and maintain consistent color usage across screens.
- **Typography**: Use clean, readable sans-serif fonts. Follow the hierarchy established by Amazon's apps with clear distinctions between headings, subheadings, and body text.
- **Spacing & Layout**: Maintain consistent padding and margins. Use a grid-based layout system for alignment and organization of elements.
- **Components**: Utilize recognizable UI patterns from Amazon apps—predictable button styles, form inputs, cards, and navigation patterns that users are already familiar with.
- **Icons**: Use intuitive, recognizable icons consistent with Amazon's icon library. Ensure proper sizing and clear visual hierarchy.
- **Shadows & Elevation**: Apply subtle shadows to create depth and distinguish interactive elements from the background.
- **Interactive Feedback**: Provide clear visual feedback on user interactions—hover states, active states, loading indicators, and animations should be smooth and responsive.
- **Accessibility**: Ensure sufficient color contrast, readable font sizes, and support for touch interactions on mobile devices. Follow accessibility standards to make the app usable by all users.
