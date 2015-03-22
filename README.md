PNGLua
======

A pure lua implementation of a PNG decoder

Usage
-----

To initialize a new png image:

    img = pngImage(<path to image>, newRowCallback, verbose)
    
Verbose is a boolean. If true, it will print messages while decoding. When the function is called, the image will be decoded. The available data from the image is as follows:

```
img.width = 0
img.height = 0
img.depth = 0
img.colorType = 0
img.pixels = { 
                1: { 
                    1: { R: ..., G: ..., B: ..., A: ...}, 
                    2: { R: ..., G: ..., B: ..., A: ...}, 
                    ...
                },
                2: { 
                    1: { R: ..., G: ..., B: ..., A: ...}, 
                    2: { R: ..., G: ..., B: ..., A: ...}, 
                    ...
                }    
                ...            
            }

```

If a new row callback is used, there will be no pixels stored in img.pixels. The new row callback is intended for fast, low memory rendering.

The format of the new callback is:

    calback(rowNum, rowTotal, rowPixels)

"rowNum" refers to the current row, "rowTotal" refers to the total number of rows in the image, and "rowPixels" refers to the table of pixels in the current row.

Support
-------

The supported colortypes are as follows:

-    Grayscale
-    Truecolor
-    Indexed
-    Greyscale/alpha
-    Truecolor/alpha

So far the module only supports 256 Colors in png-8, png-24 as well as png-32 files. and no ancillary chunks.

More than 256 colors might be supported (Bit-depths over 8) as long as they align with whole bytes. These have not been tested.

Multiple IDAT chunks of arbitrary lengths are supported. Filter type 0 is currently the only supported filter type.

Errors
-------
So far no error-checking has been implemented. No crc32 checks are done.
