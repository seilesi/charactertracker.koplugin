# Character Tracker

Character Tracker is a KOReader plugin that keeps of who and what appears in a story.

## TLDR

For people who rarely read long winded guides, these are the few things I think you should know.

- Easiest way to access it while reading is to assign a gesture in the settings > Taps and gestures > Gesture manager > (gesture of your choice) > Reader
- If you turn on underlined names you can press on any character or objects name while reading to have their profile pop up
- It tracks characters, places and any other miscellaneous topics in the compendium.
- Installation
  - Place the entire folder in the plugins folder (KOreader>Plugins).
- Names, places and objects can be underlined in the text; tapping an underlined word opens its entry.
- Selecting text offers a Character button to create or open an entry.
- If reading a series open Tools > Character Tracker > Link to series > ＋ New series, then link each later book to the same series name.
- Happy reading and I hope this makes your reading experience at least a bit more convenient.

## Overview

Tracks:

- Characters
  - aliases, occupation, type, status, age, appearance, abilities, relationships, factions, tags, traits, secrets, skills, weaknesses, belongings, residences, highlights, notes and a quote.
- Places
  - with types, descriptions and residents.
- Compendium
  - objects, artifacts, weapons, documents, concepts and magic systems, with an ownership history (if applicable)
- Families
  - named houses or clans with members and roles.

How it shows up while reading:

- Names, places and objects can be underlined in the text, tapping one opens its entry.
- Selecting text offers a Character button to create or open an entry straight from the selection.
- Linking books to a series shares one data set across every volume.

## Installation

Install by copying the folder into KOReader's plugins directory and restarting KOReader.

### Requirements

- No network access needed and no external dependencies.

### Steps

1. Download and unzip the release.
2. Connect your device by USB (or open its file manager).
3. Copy the charactertracker.koplugin folder into the plugins directory:
4. Eject the device and restart KOReader
5. Open any book, tap the top menu, go to the Tools (wrench) tab and look for Character Tracker.

Updating (if i ever do this): replace folder (or main.lua and meta.lua in the folder)

## Quick start

The fastest path is: select a name in the text, tap Character, then turn on underlining (if wanted)

1. Open a book and read until a character is named.
2. Long-press the name to select it. In the selection menu (or the dictionary popup), tap Character.
3. Choose New character from selection. The name field is pre-filled with the first word; fix it if needed, optionally add an occupation and a first note, then save.
4. Turn on underlining: Tools > Character Tracker > Underline names in text. The plugin indexes the book once (a "Indexing names…" message shows up for a couple seconds (depending on the book length)) and caches the result.
5. Tap an underlined name to open that character's card. Use its buttons to add aliases, relationships, notes and the rest.
6. Add an alias (for example if a character named Gregory is referred to as Greg, both names are indexed and underlined.
7. Repeat with places (New place from selection) and objects (New compendium entry from selection), and switch on Underline places in text / Underline objects in text if you want those marked too.
8. Reading a series? Tools > Character Tracker > Link to series > ＋ New series, then link each later book to the same series name.

## Features

Everything is reached from Tools -> Character Tracker

### Characters

Each character has a card. Edit character list opens cards in edit mode; Character list opens them read-only (with an Edit button)

| Field | What it has | Notes |
| --- | --- | --- |
| Aliases | Other names and nicknames | Each alias is underlined and matched like the main name; duplicates across characters are refused |
| Occupation | Free text | Shown as a badge in the list |
| Status | Alive, Dead, Missing, Unknown or custom | Dead adds a cause of death field |
| Type | Main, Secondary, Tertiary, Mentioned, Antagonist, Narrator | Hideable |
| Appearance | Free text | |
| Residence | Places the character lives or works, current or past | Links to the Places list |
| Last seen | Free text you set manually | Hideable |
| Age, Ability | Free text | Each hideable |
| Belongings | Free-text items, plus compendium entries they currently own | Hideable |
| Relations | Typed links to other characters | See below |
| Factions, Tags | Lists of labels | Factions can be filtered on |
| Traits | Personality traits | |
| Highlights | Quotes from the book attached to this character | |
| Secrets | Hidden facts | |
| Skills/Weak. | Two lists: skills and weaknesses | |
| Notes | Free-text notes | + Note adds one quickly |
| Quote | A signature line | |

Other card actions: Underline (turn marking off for just this character), Pin (keeps them at the top of the list), Rename, Delete.

The card also shows an automatic Occurrences block once underlining is on: how many times the name appears and where it is first seen (chapter and page).

### Relationships

A relationship links one character to another with a type and an optional sentiment.

- Types: Father, Mother, Son, Daughter, Brother, Sister, Spouse (family); Ally, Enemy, Friend, Mentor, Servant, Master, Lover (social); or a custom label.
- Sentiments: Likes, Dislikes, Loves, Hates, Fears, Admires, Respects, Distrusts, Envies, Pities, Loyal to, or custom.
- Incoming links are shown too: if A names B as Mentor, B's card lists it, and the list's relation count includes both directions.

### Places

Places form a tree. Each place has a type (Kingdom, Empire, Dukedom, Principality, County, Republic, Federation, Dictatorship, Theocracy, City-state, Province, Region, City, Town, Village, District, Fortress / castle, Building, Landmark, or custom), a description and residents.

- ＋ Sub-place adds another place within an area
- Residents records who lives or works there, current or past. It stays in sync with each character's Residence field.

### Compendium

The compendium holds things that are not people: Object, Artifact, Weapon, Document, abstract idea, Magic system, or custom.

Ownership keeps a history of owners, each with how it was acquired, how it was lost and whether they are the current owner. Current owners see the item under Belongings unless you choose Hide from belongings.

### Families

A family (house, clan, dynasty) has a description and a member list, each member with a role such as "head" or "heir". Roles appear on the character's card under Family (hideable).

### Underlining and tap-to-open

Three independent switches underline character names (with aliases), place names and compendium names. Matching is not case-sensitive.

- Tapping an underlined word opens its card, place or entry.
- Invisible underline removes the underline but keeps it tappable.
- The first index runs in the background and can be cancelled, results are cached so reopening the book is instant.
- the first 800 mentions per name are indexed by default

### Working from a text selection

Selecting text and tapping Character

- Open an existing character, place, compendium entry or family with that name.
- Add selection as highlight to… a character.
- New character / place / compendium entry / family from selection.

Each option can be hidden from this menu in settings.

### Lists, search, sort and filter

- Search characters matches names and aliases.
- Sort characters: Default (added order), Name (A–Z), Character type, Occupation, Date added, or Manual (move characters up and down yourself). Pinned characters always stay on top.
- Filter characters by status, faction or place of residence.
- Search series characters searches this book and every saved series at once.

### Series

Linking a book to a series moves its data into a shared series file, so every linked book sees the same characters, places, compendium and families.

- When you link a book that already has characters, they are merged into the series by name: lists are combined, empty fields filled, nothing overwritten.
- Link to series on a linked book offers Change series name and Unlink from series.
- The series picker's X deletes a series and all four of its files.
- Warning: if you create a book and add characters, then add it to a series, if you unlink it after that the character list will be empty.

### Export, import and undo

- Export characters writes the character list to character_tracker/exports/\<name>.json.
- Import characters picks a JSON file and merges it by name, using the same rules as series linking.
- Undo last delete restores a deleted character with its incoming relationships and residences. It keeps the last 5 deletions, for the current session only.

### Gestures and shortcuts

Five actions can be bound to gestures or shortcuts in KOReader's gesture manager: character list, edit character list, places, compendium and families.

## Configuration

All options are toggles or pickers in Tools > Character Tracker. Underline switches are remembered per book; everything else applies to every book.

| Setting | Default | Scope | Effect |
| --- | --- | --- | --- |
| Underline names in text | Off | Per book | Marks character names and aliases |
| Underline places in text | Off | Per book | Marks place names |
| Underline objects in text | Off | Per book | Marks compendium names |
| Invisible underline | Off | Per book | Keeps names tappable but draws no line |
| Tapping a name opens the read-only view | Off | Global | Tap shows the read-only card instead of the edit card |
| Max matches per name | 800 | Global | Mentions indexed per name: 400, 800, 1200, 1600, unlimited, or custom |
| Re-index now | — | Per book | Ignores the cache and rescans the book |
| Hide character type / age / ability / belongings / last seen / family roles | Off | Global | Removes that field from cards and the list |
| Hide index limit warning | Off | Global | Stops the note that a name hit the match cap |
| Hide new character / highlight / place / compendium / family (when selecting text) | Off | Global | Trims the selection menu |

### Choosing a match cap.

- Mentions are counted from the start of the book; later ones are not underlined. Above 1,600 the plugin warns that the first index will be slower and the cache larger, which can cause lag on e-ink devices(This is untested so do as you please and see at which point it starts to cause lag/slow index times per your own device)

## Troubleshooting and FAQ

| Problem | Likely cause | Fix |
| --- | --- | --- |
| Character Tracker is missing from the Tools menu | Folder not named .koplugin, meta.lua is missing, or no book open | Check the folder layout in Installation; the menu only appears inside an open book |
| Nothing is underlined | Underlining is off for this book, or the character's own Underline is off | Turn on Underline names in text, then Re-index now |
| Later mentions are not underlined | The name hit the match cap (800 by default) | Raise Max matches per name, the card warns when this happens |
| Opening a book is slow the first time | The first full index of a long book | Wait, or cancel and lower the match cap; later opens use the cache |
| Tapping a saved highlight on a name opens the character instead | Taps on underlined words go to the plugin first | Tap the highlight away from the name, or turn off Underline on that character's card |
| My characters vanished | Data file could not be read | Look for \<book>.characters.json.corrupt next to the book; fix the JSON and rename it back |
| Undo last delete says nothing to restore | Undo only covers deletions since KOReader was opened | Re-create the character or import from an export |
| Data missing after moving a book | Book-local data files sit next to the book file | Move the .characters.json, .places.json, .compendium.json and .families.json files with it |

Does it need the internet? No.

Will it spoil the book? No, this is fully manual, it will only show what you typed.

Can I edit the data on a computer? Yes. The files are plain JSON; close the book on the device first so your edits are not overwritten.

When is data saved? About 2 seconds after each change, and again when you close the book or the device sleeps.

Can I share my notes with a friend? Use Export characters and send them the JSON; they use Import characters. Places, compendium and families are not part of the export.

## FYI

- Unlinking a book from a series empties its character list  and saves that empty list over the book's own character file. Export first if you may want the book-local list back.
- Export and import are characters only
- Undo keeps the last 5 deletions and is cleared when KOReader closes. Deleting places, compendium entries and families cannot be undone.
- Series files are named from the series name with punctuation stripped, "Lorem" and "lorem" share the same file "Lorem!" and "Lorem" are the same
- Matching is plain text, case-insensitive. Very short aliases may also match inside other words; turn off Underline for that character if it gets noisy.
- Notes do not record the page or chapter where they were written.

## Translations

- If you see this and wish to make a translation you are free to make one, and rerelease this repo
- If you want to request a translation please open an issue.
