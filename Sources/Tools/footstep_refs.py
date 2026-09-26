#!/usr/bin/env python3
"""Turns the SoundGen keys of the katar animations into SoundGenRef keys, which sound nothing.

Every katar animation plays over the engine's own animation of the moment - its parent - which keeps
playing underneath and keeps sounding its own keys. The engine sounds a "SoundGen: ..." key from
whichever animation it is in (character.cpp, CharacterController::handleTextKey), and so do the Lua
mods listening for them (MercyCAO, Dynamic Reticle's sneaking step, footstep sound mods), so a katar
walk carrying the fist's footsteps sounded every step twice. Renamed, the keys stay in the files -
where the steps fall, to read, and for make_third_person_anims.py to match the third-person legs
against - but name nothing anything listens for.

    python3 footstep_refs.py <.kf files, or folders of them>

Safe to run twice. import_h2h_set.py, make_katar_1h_movement.py and make_third_person_anims.py all do
this to what they write.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

SOUND = "SoundGen"
REF = "SoundGenRef"


def _swap(text, old, new):
    sep = "\r\n" if "\r\n" in text else "\n"
    lines = []
    for line in text.split(sep):
        group, colon, rest = line.partition(":")
        if colon and group.strip().lower() == old.lower():
            line = new + colon + rest
        lines.append(line)
    return sep.join(lines)


def to_ref(text):
    """A text key's text with its SoundGen lines renamed."""
    return _swap(text, SOUND, REF)


def from_ref(text):
    """And back, for tools that read them as footsteps."""
    return _swap(text, REF, SOUND)


def rename(path):
    """Renames a .kf's SoundGen keys in place. Returns how many keys changed."""
    import mirror_weapon_track  # noqa: F401  (puts the es3 library on the path)
    from es3.nif import NiStream, NiTextKeyExtraData
    stream = NiStream()
    stream.load(path)
    changed = 0
    for extra in stream.objects_of_type(NiTextKeyExtraData):
        keys = extra.keys.copy()  # a structured array: (time, text)
        for i in range(len(keys)):
            new = to_ref(keys[i][1])
            if new != keys[i][1]:
                keys[i] = (keys[i][0], new)
                changed += 1
        extra.keys = keys
    if changed:
        stream.save(path)
    return changed


def main():
    paths = []
    for item in sys.argv[1:]:
        if os.path.isdir(item):
            paths += sorted(os.path.join(item, n) for n in os.listdir(item) if n.lower().endswith(".kf"))
        else:
            paths.append(item)
    if not paths:
        sys.exit(__doc__)
    for path in paths:
        print("%-28s %d keys renamed" % (os.path.basename(path), rename(path)))


if __name__ == "__main__":
    main()
