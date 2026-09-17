#ifndef TEXT_UTF8_H_8I8S2ODM
#define TEXT_UTF8_H_8I8S2ODM

#include <oak/debug.h>

namespace utf8
{
	inline uint32_t to_ch (std::string const& str)
	{
		ASSERT(!str.empty());

		uint32_t value = (unsigned char)str[0];
		size_t mb_length = 1;

		if((value & 0xC0) == 0xC0) // multi-byte
		{
			// Lenient, as iterator_t::fetch is: a lead byte that announces more
			// bytes than the string has, or is followed by a non-continuation byte,
			// is returned as the byte itself (fuzzer, 2026-09-16).
			while(mb_length < 8 && (value & (1 << (7-mb_length))))
				++mb_length;
			if(mb_length > 6 || str.size() < mb_length)
				return (unsigned char)str[0];

			value = value & ((1 << (7-mb_length))-1);
			for(size_t i = 1; i < mb_length; ++i)
			{
				if(((unsigned char)str[i] & 0xC0) != 0x80)
					return (unsigned char)str[0];
				value = (value << 6) | ((unsigned char)str[i] & 0x3F);
			}
		}
		return value;
	}

	inline std::string to_s (uint32_t ch)
	{
		char res[6];
		size_t bitsLeft = 0, strLen = 1;
		if(ch <= 0x7F) // 0xxxxxxx
			res[0] = ((ch >> (bitsLeft =  0)) & 0x7F) | 0x00;
		else if(ch <= 0x7FF) // 110xxxxx 10xxxxxx
			res[0] = ((ch >> (bitsLeft =  6)) & 0x1F) | 0xC0;
		else if(ch <= 0xFFFF) // 1110xxxx 10xxxxxx 10xxxxxx
			res[0] = ((ch >> (bitsLeft = 12)) & 0x0F) | 0xE0;
		else if(ch <= 0x1FFFFF) // 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
			res[0] = ((ch >> (bitsLeft = 18)) & 0x07) | 0xF0;
		else if(ch <= 0x3FFFFFF) // 111110xx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
			res[0] = ((ch >> (bitsLeft = 24)) & 0x03) | 0xF8;
		else // if(ch <= 0x7FFFFFFF) // 1111110x 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
			res[0] = ((ch >> (bitsLeft = 30)) & 0x01) | 0xFC;

		while(bitsLeft >= 6)
		{
			bitsLeft -= 6;
			res[strLen++] = ((ch >> bitsLeft) & 0x3F) | 0x80;
		}

		return std::string(res, res + strLen);
	}

	template <typename _Iter>
	struct iterator_t

	{

		// The typedefs std::iterator provided, spelled out: it is deprecated since C++17.

		using iterator_category = std::bidirectional_iterator_tag;

		using value_type        = uint32_t;

		using difference_type   = std::ptrdiff_t;

		using pointer           = value_type*;

		using reference         = value_type&;
		typedef iterator_t self;

		iterator_t (_Iter const& base_iterator) : base_iterator(base_iterator) { }
		iterator_t () { }

		self& operator++ ()                       { fetch(); std::advance(base_iterator, mb_length); return *this; }
		self& operator-- ()                       { do { --base_iterator; } while((*base_iterator & 0xC0) == 0x80); return *this; }

		bool operator== (self const& rhs) const   { return base_iterator == rhs.base_iterator; }
		bool operator!= (self const& rhs) const   { return base_iterator != rhs.base_iterator; }

		uint32_t& operator* ()                    { fetch(); return value; }
		uint32_t const& operator* () const        { fetch(); return value; }

		_Iter operator& () const                  { return base_iterator; }
		ssize_t length () const                   { fetch(); return mb_length; }

	private:
		// Lenient, not asserting: this iterator runs over strings that came from
		// files — property lists, bundle items, documents — and an assertion here
		// ends the process. An invalid lead byte (0xFE, 0xFF) is a one-byte
		// character; a sequence cut short by a non-continuation byte is the bytes
		// seen so far, and iteration resumes at the byte that broke it. Found by
		// the fuzzer on 2026-09-16: a bundle item with one stray byte in a string
		// took the process down in plist::to_s.
		void fetch () const
		{
			_Iter it = base_iterator;
			value = *it;
			mb_length = 1;

			if((value & 0xC0) == 0xC0) // multi-byte
			{
				ssize_t expected = 1;
				while(expected < 8 && (value & (1 << (7-expected))))
					++expected;

				if(expected > 6) // 0xFE or 0xFF: not a lead byte
					return;

				value = value & ((1 << (7-expected))-1);
				for(ssize_t i = 1; i < expected; ++i)
				{
					uint32_t const next = *++it;
					if((next & 0xC0) != 0x80)
						break;
					value = (value << 6) | (next & 0x3F);
					mb_length = i + 1;
				}
			}
		}

		_Iter base_iterator;
		mutable uint32_t value;
		mutable ssize_t mb_length;
	};

	template <typename _BaseIter> iterator_t<_BaseIter> make (_BaseIter const& base) { return iterator_t<_BaseIter>(base); }

	struct validate_t
	{
		validate_t () : len(0), seen(0), success(true) { }
		bool is_valid () const { return success && len == 0; }

		template <typename _Iter>
		bool scan (_Iter const& first, _Iter const& last)
		{
			for(_Iter it = first; it != last && success; ++it)
			{
				typename std::iterator_traits<_Iter>::value_type ch = *it;
				if(len) // we are in a multi-byte sequence
				{
					if((ch & 0xC0) == 0x80)
					{
						if(++seen == len)
							len = seen = 0;
					}
					else
					{
						success = false;
					}
				}
				else if((ch & 0xC0) == 0x80)
				{
					success = false;
				}
				else if((ch & 0x80) == 0x80)
				{
					// Bounded: for 0xFF every bit is set, and the unbounded loop shifted
					// by -1 before the `> 6` check below could reject it (UBSan, from the
					// fuzzer's first minute, 2026-09-16).
					size_t numBytes = 1;
					while(numBytes < 8 && (ch & (1 << (7-numBytes))))
						++numBytes;

					if(numBytes > 6)
						success = false;

					len = numBytes;
					seen = 1;
				}

// #ifndef NDEBUG
// 				if(!success)
// 				{
// 					fprintf(stderr, "%zu / %zu\n", seen, len);
// 					std::vector<char> v;
// 					text::hex_dump(first, it + 1, back_inserter(v));
// 					fprintf(stderr, "%.*s\n", (int)v.size(), &v[0]);
// 				}
// #endif
			}
			return success;
		}

	private:
		size_t len, seen;
		bool success;
	};

	template <typename _Iter>
	bool is_valid (_Iter const& first, _Iter const& last)
	{
		validate_t validate;
		return validate.scan(first, last) && validate.is_valid();
	}

	template <typename T>
	struct multibyte
	{
		static bool partial (T ch)       { return ch & 0x80; }
		static bool is_start (T ch)      { return (ch & 0xC0) == 0xC0; }
		static size_t length (T ch)      {
			size_t numBytes = 1;
			if(is_start(ch))
			{
				ASSERT((ch & 0xF8) != 0xF8);
				while((ch & (1 << (7-numBytes))) && numBytes < 6)
					++numBytes;
			}
			return numBytes;
		}
	};

	static struct { char mask, expect; } const UTF8LengthCodes[] =
	{
		{ 0b10000000, 0b00000000 },
		{ 0b11100000, 0b11000000 },
		{ 0b11110000, 0b11100000 },
		{ 0b11111000, 0b11110000 },
		{ 0b11111100, 0b11111000 },
		{ 0b11111110, 0b11111100 },
	};

	template <typename _Iter>
	_Iter find_safe_end (_Iter const& first, _Iter const& last)
	{
		_Iter it = last;
		for(auto const& code : UTF8LengthCodes)
		{
			if(it == first || (*--it & code.mask) == code.expect)
				return last;
			if((*it & 0b11000000) == 0b11000000)
				return it;
		}
		return last;
	}

	template <typename _Iter>
	_Iter remove_malformed (_Iter it, _Iter const& last)
	{
		auto dst = it;
		while(it != last)
		{
			auto bt = it;
			bool valid = false;
			for(auto const& code : UTF8LengthCodes)
			{
				if(valid = ((*bt & code.mask) == code.expect))
					break;
				if(++it == last || (*it & 0b11000000) != 0b10000000)
					break;
			}

			if(valid)
					dst = dst == bt ? ++it : std::copy(bt, ++it, dst);
			else	it = ++bt;
		}
		return dst;
	}

} /* utf8 */

namespace diacritics
{
	template <typename _Iter>
	struct iterator_t

	{

		// The typedefs std::iterator provided, spelled out: it is deprecated since C++17.

		using iterator_category = std::bidirectional_iterator_tag;

		using value_type        = uint32_t;

		using difference_type   = std::ptrdiff_t;

		using pointer           = value_type*;

		using reference         = value_type&;
		typedef iterator_t self;

		iterator_t (utf8::iterator_t<_Iter> const& first, utf8::iterator_t<_Iter> const& last) : current(first), stop(last) { }

		self& operator++ () { fetch(); current = next; return *this; }

		self& operator-- ()
		{
			next = current;
			while(true)
			{
				uint32_t ch = *--current;
				if(ch < 0x100 || !CFCharacterSetIsLongCharacterMember(CFCharacterSetGetPredefined(kCFCharacterSetNonBase), ch))
					break;
			}
			return *this;
		}

		self operator+ (ssize_t dist) const
		{
			self res(*this);
			for(; dist > 0; --dist)
				++res;
			for(; dist < 0; ++dist)
				--res;
			return res;
		}

		self operator- (ssize_t dist) const
		{
			return *this + -dist;
		}

		ssize_t operator- (self const& rhs) const
		{
			ssize_t res = 0;
			for(self tmp(rhs); tmp != *this; ++tmp)
				++res;
			return res;
		}

		bool operator== (self const& rhs) const    { return current == rhs.current; }
		bool operator!= (self const& rhs) const    { return current != rhs.current; }

		uint32_t& operator* ()                     { ASSERT(current != stop); return *current; }
		uint32_t const& operator* () const         { ASSERT(current != stop); return *current; }

		_Iter operator& () const                   { return &current; }
		ssize_t length () const                    { fetch(); return &next - &current; }

	private:
		utf8::iterator_t<_Iter> current, stop;
		mutable utf8::iterator_t<_Iter> next;

		void fetch () const
		{
			ASSERT(current != stop);
			for(next = current; ++next != stop; )
			{
				uint32_t ch = *next;
				if(ch < 0x100 || !CFCharacterSetIsLongCharacterMember(CFCharacterSetGetPredefined(kCFCharacterSetNonBase), ch))
					break;
			}
		}
	};

	template <typename _BaseIter> iterator_t<_BaseIter> begin_of (_BaseIter const& first, _BaseIter const& last) { return iterator_t<_BaseIter>(utf8::iterator_t<_BaseIter>(first), utf8::iterator_t<_BaseIter>(last)); }
	template <typename _BaseIter> iterator_t<_BaseIter> end_of (_BaseIter const& first, _BaseIter const& last)   { return iterator_t<_BaseIter>(utf8::iterator_t<_BaseIter>(last), utf8::iterator_t<_BaseIter>(last)); }

	template <typename _BaseIter>
	struct range_t
	{
		typedef iterator_t<_BaseIter> const_iterator;

		range_t (iterator_t<_BaseIter> const& first, iterator_t<_BaseIter> const& last) : first(first), last(last) { }
		iterator_t<_BaseIter> begin () const                     { return first; }
		iterator_t<_BaseIter> end () const                       { return last; }

		std::reverse_iterator< iterator_t<_BaseIter> > rbegin () { return std::reverse_iterator< iterator_t<_BaseIter> >(last); }
		std::reverse_iterator< iterator_t<_BaseIter> > rend ()   { return std::reverse_iterator< iterator_t<_BaseIter> >(first); }

	private:
		iterator_t<_BaseIter> first, last;
	};

	template <typename _BaseIter>
	range_t<_BaseIter> make_range (_BaseIter const& first, _BaseIter const& last)
	{
		return range_t<_BaseIter>(iterator_t<_BaseIter>(utf8::iterator_t<_BaseIter>(first), utf8::iterator_t<_BaseIter>(last)), iterator_t<_BaseIter>(utf8::iterator_t<_BaseIter>(last), utf8::iterator_t<_BaseIter>(last)));
	}

} /* diacritics */

#endif /* end of include guard: TEXT_UTF8_H_8I8S2ODM */
