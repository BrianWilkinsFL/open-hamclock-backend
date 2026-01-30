# This file will do test decompressions of the zlib compressed bitmaps for HamClock
# Replace input and output filenames below
# It is a throwaway script
import zlib, sys

with open("map-D-660x330-Clouds.bmp.z", "rb") as f:
   data = zlib.decompress(f.read())

with open("output.bmp", "wb") as f:
   f.write(data)
