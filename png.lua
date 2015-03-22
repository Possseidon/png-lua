-- The MIT License (MIT)

-- Copyright (c) 2013 DelusionalLogic

-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
-- the Software, and to permit persons to whom the Software is furnished to do so,
-- subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
-- FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
-- COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
-- IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
-- CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


local class = require("pngLua/30log")
local deflate = require("pngLua/deflate")
local Stream = require("pngLua/stream")
local deepCopy = require("pngLua/deepCopy")

local function getDataIHDR(stream, length)
    local data = {}
    data["width"] = stream:readInt()
    data["height"] = stream:readInt()
    data["bitDepth"] = stream:readByte()
    data["colorType"] = stream:readByte()
    data["compression"] = stream:readByte()
    data["filter"] = stream:readByte()
    data["interlace"] = stream:readByte()
    return data
end

local function getDataIDAT(stream, length, oldData)
    local data = {}
    if (oldData == nil) then
        data.data = stream:readChars(length)
    else
        data.data = oldData.data .. stream:readChars(length)
    end
    return data
end

local function getDataPLTE(stream, length)
    local data = {}
    data["numColors"] = math.floor(length/3)
    data["colors"] = {}
    for i = 1, data["numColors"] do
        data.colors[i] = {
            R = stream:readByte(),
            G = stream:readByte(),
            B = stream:readByte()
        }
    end
    return data
end

--adds data in chunk to table of chunk types.
--IDAT data is combined into a single table entry
local function extractChunkData(stream)
    local chunkData = {}
    local length
    local type
    local crc

    while type ~= "IEND" do
        length = stream:readInt()
        type = stream:readChars(4)
        if (type == "IHDR") then
            chunkData[type] = getDataIHDR(stream, length)
        elseif (type == "IDAT") then
            chunkData[type] = getDataIDAT(stream, length, chunkData[type])
        elseif (type == "PLTE") then
            chunkData[type] = getDataPLTE(stream, length)
        else
            stream:seek(length)
        end
        crc = stream:readChars(4)
    end

    return chunkData
end

local function DEC_HEX(IN)
    local B, K, OUT, I, D = 16, "0123456789ABCDEF", "", 0

    while IN>0 do
        I = I + 1
        IN, D = math.floor(IN/B), (IN%B)+1
        OUT = string.sub(K,D,D)..OUT
    end
    if (OUT == "") then
        OUT = "0"
    end

    return tonumber(OUT, 16)
end

local function makePixel(stream, depth, colorType, palette)
    local bps = math.floor(depth/8) --bits per sample
    local pixelData = { R = 0, G = 0, B = 0, A = 0 }

    if colorType == 0 then
        local grey = stream:readInt(bps)
        pixelData.R = grey
        pixelData.G = grey
        pixelData.B = grey
        pixelData.A = 255
    elseif colorType == 2 then
        pixelData.R = stream:readInt(bps)
        pixelData.G = stream:readInt(bps)
        pixelData.B = stream:readInt(bps)
        pixelData.A = 255
    elseif colorType == 3 then
        local index = stream:readInt(bps)+1
        local color = palette.colors[index]
        pixelData.R = color.R
        pixelData.G = color.G
        pixelData.B = color.B
        pixelData.A = 255
    elseif colorType == 4 then
        local grey = stream:readInt(bps)
        pixelData.R = grey
        pixelData.G = grey
        pixelData.B = grey
        pixelData.A = stream:readInt(bps)
    elseif colorType == 6 then
        pixelData.R = stream:readInt(bps)
        pixelData.G = stream:readInt(bps)
        pixelData.B = stream:readInt(bps)
        pixelData.A = stream:readInt(bps)
    end

    return pixelData
end

local function bitFromColorType(colorType)
    if colorType == 0 then return 1 end
    if colorType == 2 then return 3 end
    if colorType == 3 then return 1 end
    if colorType == 4 then return 2 end
    if colorType == 6 then return 4 end
    error 'Invalid colortype'
end

--Stolen right from w3.
local function paethPredict(a, b, c)
    local p = a + b - c
    local varA = math.abs(p - a)
    local varB = math.abs(p - b)
    local varC = math.abs(p - c)

    if varA <= varB and varA <= varC then 
        return a 
    elseif varB <= varC then 
        return b 
    else
        return c
    end
end

local function getPixelRow(stream, depth, colorType, palette, length)
    local pixels = {}
    local filterType = 0
    local bpp = math.floor(depth/8) * bitFromColorType(colorType)
    local bpl = bpp*length

    filterType = stream:readByte()
    stream:seek(-1)
    stream:writeByte(0)
    local startLoc = stream.position
    if filterType == 0 then
        for i = 1, length do
            pixels[i] = makePixel(stream, depth, colorType, palette)
        end
    elseif filterType == 1 then
        for i = 1, length do
            for j = 1, bpp do
                local curByte = stream:readByte()
                stream:seek(-(bpp+1))
                local lastByte = 0
                if stream.position >= startLoc then lastByte = stream:readByte() or 0 else stream:readByte() end
                stream:seek(bpp-1)
                stream:writeByte((curByte + lastByte) % 256)
            end
            stream:seek(-bpp)
            pixels[i] = makePixel(stream, depth, colorType, palette)
        end
    elseif filterType == 2 then
        for i = 1, length do
            for j = 1, bpp do
                local curByte = stream:readByte()
                stream:seek(-(bpl+2))
                local lastByte = stream:readByte() or 0
                stream:seek(bpl)
                stream:writeByte((curByte + lastByte) % 256)
            end
            stream:seek(-bpp)
            pixels[i] = makePixel(stream, depth, colorType, palette)
        end
    elseif filterType == 3 then
        for i = 1, length do
            for j = 1, bpp do
                local curByte = stream:readByte()
                stream:seek(-(bpp+1))
                local lastByte = 0
                if stream.position >= startLoc then lastByte = stream:readByte() or 0 else stream:readByte() end
                stream:seek(-(bpl)+bpp-2)
                local priByte = stream:readByte() or 0
                stream:seek(bpl)
                stream:writeByte((curByte + math.floor((lastByte+priByte)/2)) % 256)
            end
            stream:seek(-bpp)
            pixels[i] = makePixel(stream, depth, colorType, palette)
        end
    elseif filterType == 4 then
        for i = 1, length do
            for j = 1, bpp do
                local curByte = stream:readByte()
                stream:seek(-(bpp+1))
                local lastByte = 0
                if stream.position >= startLoc then lastByte = stream:readByte() or 0 else stream:readByte() end
                stream:seek(-(bpl + 2 - bpp))
                local priByte = stream:readByte() or 0
                stream:seek(-(bpp+1))
                local lastPriByte = 0
                if stream.position >= startLoc - (length * bpp + 1) then lastPriByte = stream:readByte() or 0 else stream:readByte() end
                stream:seek(bpl + bpp)
                stream:writeByte((curByte + paethPredict(lastByte, priByte, lastPriByte)) % 256)
            end
            stream:seek(-bpp)
            pixels[i] = makePixel(stream, depth, colorType, palette)
        end
    end
    return pixels
end

local pngImage = class()

pngImage.__name = "PNG"
pngImage.width = 0
pngImage.height = 0
pngImage.depth = 0
pngImage.colorType = 0
pngImage.rows = {}

function pngImage:__init(path, progCallback)
    local str = Stream({inputF = path})
    local chunks
    local output
    local imStr

    if str:readChars(8) ~= "\137\080\078\071\013\010\026\010" then 
        error 'Not a PNG' 
    end

    print("Parsing Chunks...")
    local chunkData = extractChunkData(str)

    self.width = chunkData.IHDR.width
    self.height = chunkData.IHDR.height
    self.depth = chunkData.IHDR.bitDepth
    self.colorType = chunkData.IHDR.colorType

    output = {}
    print("Deflating...")
    deflate.inflate_zlib {
        input = chunkData.IDAT.data, 
        output = function(byte) 
            output[#output+1] = string.char(byte) 
        end, 
        disable_crc = true
    }
    imStr = Stream({input = table.concat(output)})

    for i = 1, self.height do
        self.rows[i] = getPixelRow(imStr, self.depth, self.colorType, chunkData.PLTE, self.width)
        if progCallback ~= nil then 
            progCallback(i, self.height, self.rows[i])
        end
    end
end

function pngImage:getPixel(x, y)
    local pixel = self.rows[y][x]
    return pixel
end

return pngImage