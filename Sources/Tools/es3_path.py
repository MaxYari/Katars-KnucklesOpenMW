"""Puts Greatness7's es3 NIF library on the path: import this before `from es3.nif import ...`.

es3 ships inside the io_scene_mw Blender add-on and is used wherever that is installed, or from the
add-on's 'lib' folder named by IO_SCENE_MW. It needs numpy.
"""
import os
import sys

MISSING = ("Could not find the es3 library (%s). Install Greatness7's io_scene_mw Blender add-on, or "
           "point IO_SCENE_MW at its 'lib' folder.")


def find_lib():
    """es3 ships inside Greatness7's Blender add-on; use it wherever it is installed."""
    for root in (
        os.environ.get("IO_SCENE_MW", ""),
        os.path.expanduser("~/.config/blender"),
        os.path.expanduser("~/Library/Application Support/Blender"),
        os.path.expanduser("~/AppData/Roaming/Blender Foundation/Blender"),
    ):
        if not root:
            continue
        if os.path.isdir(os.path.join(root, "es3")):
            return root
        for dirpath, dirnames, _ in os.walk(root):
            if os.path.basename(dirpath) == "lib" and "es3" in dirnames:
                return dirpath
    return None


lib = find_lib()
if lib and lib not in sys.path:
    sys.path.append(lib)
