package com.timhxl.hallbeat

private val sharpPitchNames = listOf("C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B")
private val flatPitchNames = listOf("C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B")
internal fun notePitchNames(preferFlats: Boolean): List<String> = if (preferFlats) flatPitchNames else sharpPitchNames

internal data class NoteChoice(val pitch: Int, val label: String, val flats: Boolean = false)
internal val keyNoteChoices = listOf(
    NoteChoice(0, "C"), NoteChoice(1, "C♯"), NoteChoice(1, "D♭", true), NoteChoice(2, "D"), NoteChoice(3, "D♯"), NoteChoice(3, "E♭", true),
    NoteChoice(4, "E"), NoteChoice(5, "F"), NoteChoice(6, "F♯"), NoteChoice(6, "G♭", true), NoteChoice(7, "G"), NoteChoice(8, "G♯"),
    NoteChoice(8, "A♭", true), NoteChoice(9, "A"), NoteChoice(10, "A♯"), NoteChoice(10, "B♭", true), NoteChoice(11, "B")
)
