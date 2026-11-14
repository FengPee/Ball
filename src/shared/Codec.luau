-- Packs an arena snapshot into a small buffer for an UnreliableRemoteEvent
-- (those are capped at roughly 1000 bytes, so we keep each entity to 26 bytes).
local Codec = {}

local HEADER = 4 -- plot u8, count u8, seq u16
local ENTITY = 26 -- id u16, kind u8, tier u8, wtype u8, r u8, x/z/angle/hp/maxHp f32

function Codec.encode(plot: number, seq: number, entities): buffer
	local n = math.min(#entities, 30)
	local b = buffer.create(HEADER + ENTITY * n)
	buffer.writeu8(b, 0, plot)
	buffer.writeu8(b, 1, n)
	buffer.writeu16(b, 2, seq)
	local o = HEADER
	for i = 1, n do
		local e = entities[i]
		buffer.writeu16(b, o, e.id)
		buffer.writeu8(b, o + 2, e.kind)
		buffer.writeu8(b, o + 3, e.tier)
		buffer.writeu8(b, o + 4, e.wtype)
		buffer.writeu8(b, o + 5, math.clamp(math.floor(e.r * 10 + 0.5), 0, 255))
		buffer.writef32(b, o + 6, e.x)
		buffer.writef32(b, o + 10, e.z)
		buffer.writef32(b, o + 14, e.angle)
		buffer.writef32(b, o + 18, math.max(e.hp, 0))
		buffer.writef32(b, o + 22, e.maxHp)
		o += ENTITY
	end
	return b
end

function Codec.decode(b: buffer)
	local plot = buffer.readu8(b, 0)
	local n = buffer.readu8(b, 1)
	local seq = buffer.readu16(b, 2)
	local list = table.create(n)
	local o = HEADER
	for i = 1, n do
		list[i] = {
			id = buffer.readu16(b, o),
			kind = buffer.readu8(b, o + 2),
			tier = buffer.readu8(b, o + 3),
			wtype = buffer.readu8(b, o + 4),
			r = buffer.readu8(b, o + 5) / 10,
			x = buffer.readf32(b, o + 6),
			z = buffer.readf32(b, o + 10),
			angle = buffer.readf32(b, o + 14),
			hp = buffer.readf32(b, o + 18),
			maxHp = buffer.readf32(b, o + 22),
		}
		o += ENTITY
	end
	return plot, seq, list
end

-- True if `seq` is newer than `last` (handles wrap-around at 65536).
function Codec.isNewer(seq: number, last: number?): boolean
	if last == nil then
		return true
	end
	local diff = (seq - last) % 65536
	return diff > 0 and diff < 32768
end

return Codec
