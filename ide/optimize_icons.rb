# Re-encode the document icons into ide/gen/icons/, smaller and pixel-for-pixel
# the same. Called from seed_xcodeproj.rb, which then points the app's copy phase
# at the generated copies.
#
# Why this exists. `Applications/TextMate/icons` is the `document-icons`
# **submodule** — out of scope for edits — so the 54 icons ship exactly as
# upstream encoded them, in a format that predates 10.5:
#
#     is32 s8mk   16x16    RLE + mask       788 bytes
#     il32 l8mk   32x32    RLE + mask     2,849
#     it32 t8mk   128x128  RLE + mask    32,170   <- t8mk alone is an
#     ic09        512x512  PNG          141,063      *uncompressed* 16 KB mask
#
# Two things are recoverable there, both lossless:
#
#   1. The 128x128 pair costs 32 KB for one image. As PNG (ic07) it is 12 KB.
#      iconutil does this conversion, and it is the right tool for it — decoding
#      RLE + mask by hand is exactly the kind of thing that would look fine in
#      review and render as garbage in the file browser.
#   2. Every PNG rep is under-compressed. Re-deflating the *same filtered
#      scanlines* at level 9 with Z_FILTERED takes the 512px rep from 141 KB to
#      117 KB with the decoded pixels bit-identical — this touches only the
#      zlib stream, never the image data.
#
# Order matters and is not obvious: iconutil re-encodes PNG data on its way into
# an .icns, so optimizing the .iconset first and then calling iconutil throws the
# work away (measured — the output came back byte-identical). The recompression
# has to run over the finished .icns.
#
# Measured 2026-08-18 on the 54 document icons: 10.2 MB -> 7.7 MB.
#
# One trap, caught by checking rather than by looking: the `.iconset` format has
# no 48x48 slot, so a plain iconutil round-trip silently drops the ih32/h8mk pair
# from the nine `TextMate *.icns` that carry one. Nothing errors and the icons
# still render — macOS just resamples 48px from another rep. Those chunks are
# spliced back from the source below; they cost 6.8 KB each, which is not worth
# the "probably fine".
#
# What is NOT preserved: iconutil's il32 -> ic05 conversion moves ~8 pixels per
# 32x32 icon by a rounding step in its own premultiply. Verified as edge
# antialiasing, not structure. The 16/128/512 reps come back bit-identical.

require "fileutils"
require "zlib"
require "digest"

# Re-deflate a PNG's IDAT without touching the filtered scanlines it decodes to.
# The pixels are by construction identical; only the compressed stream changes.
# Returns the input unchanged if the re-encode is not smaller.
def recompress_png(data)
  return data unless data[0, 8] == "\x89PNG\r\n\x1a\n".b

  idat = +"".b
  other = []
  off = 8
  while off + 8 <= data.bytesize
    len  = data[off, 4].unpack1("N")
    type = data[off + 4, 4]
    body = data[off + 8, len]
    type == "IDAT" ? idat << body : other << [type, body]
    off += 12 + len
  end
  return data if idat.empty?

  raw = Zlib::Inflate.inflate(idat)
  z   = Zlib::Deflate.new(Zlib::BEST_COMPRESSION, Zlib::MAX_WBITS, 9, Zlib::FILTERED)
  new = z.deflate(raw, Zlib::FINISH); z.close
  return data if new.bytesize >= idat.bytesize

  out = +"\x89PNG\r\n\x1a\n".b
  chunk = ->(type, body) { out << [body.bytesize].pack("N") << type << body << [Zlib.crc32(type + body)].pack("N") }
  other.each do |type, body|
    chunk.call("IDAT", new) if type == "IEND"
    chunk.call(type, body)
  end
  out
end

# Split an .icns container into [type, payload] pairs.
def icns_chunks(data)
  out = []
  off = 8
  while off + 8 <= data.bytesize
    type = data[off, 4]
    len  = data[off + 4, 4].unpack1("N")
    break if len < 8
    out << [type, data[off + 8, len - 8]]
    off += len
  end
  out
end

def icns_pack(chunks)
  body = chunks.map { |type, p| type + [p.bytesize + 8].pack("N") + p }.join
  "icns" + [body.bytesize + 8].pack("N") + body
end

# Recompress every rep that holds a PNG, and carry over any rep iconutil could not
# represent in an .iconset (see the 48x48 note above). ic04/ic05 are raw ARGB and
# are left alone. The round-tripped file carries no TOC — which would otherwise
# need its offsets rewritten too — so assert that rather than trust it.
CARRY_OVER = %w[ih32 h8mk].freeze

def recompress_icns(path, source)
  chunks = icns_chunks(File.binread(path))
  raise "#{File.basename(path)}: unexpected TOC, chunk offsets would need rewriting" if chunks.assoc("TOC ")

  have = chunks.map(&:first)
  icns_chunks(File.binread(source)).each do |type, payload|
    chunks << [type, payload] if CARRY_OVER.include?(type) && !have.include?(type)
  end

  File.binwrite(path, icns_pack(chunks.map { |type, p| [type, recompress_png(p)] }))
end

# Returns { source_path => generated_path } for every .icns given. Regenerates
# only when the source is newer than the output, because this runs on every seed
# and iconutil over 54 icons is not free.
def optimize_icons(root, sources, out_dir)
  abs_out = File.join(root, out_dir)
  FileUtils.mkdir_p(abs_out)
  mapping = {}

  sources.each do |rel|
    src = File.join(root, rel)
    dst = File.join(abs_out, File.basename(rel))
    mapping[rel] = File.join(out_dir, File.basename(rel))
    next if File.exist?(dst) && File.mtime(dst) >= File.mtime(src)

    iconset = File.join(abs_out, "#{File.basename(rel, '.icns')}.iconset")
    FileUtils.rm_rf(iconset)
    # iconutil is the decoder for the pre-10.5 RLE reps. If it cannot read this
    # icon, ship the original rather than a half-converted one.
    unless system("iconutil", "-c", "iconset", src, "-o", iconset, out: File::NULL, err: File::NULL) &&
           system("iconutil", "-c", "icns", iconset, "-o", dst, out: File::NULL, err: File::NULL)
      warn "optimize_icons: iconutil failed on #{rel}, shipping it unchanged"
      FileUtils.cp(src, dst)
      FileUtils.rm_rf(iconset)
      next
    end
    FileUtils.rm_rf(iconset)
    recompress_icns(dst, src)
  end

  mapping
end
