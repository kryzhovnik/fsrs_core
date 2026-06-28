# frozen_string_literal: true
module FsrsCore
  module Validate
    module_function

    U32_MAX = 4_294_967_295

    def real(x, name)
      f = Float(x)
      raise ValidationError, "#{name} must be finite, got #{x.inspect}" unless f.finite?
      f
    rescue ArgumentError, TypeError, RangeError
      raise ValidationError, "#{name} must be a real number, got #{x.inspect}"
    end

    def retention(r)
      v = real(r, "desired_retention")
      raise ValidationError, "desired_retention must be in (0, 1], got #{r.inspect}" unless v > 0.0 && v <= 1.0
      v
    end

    def parameters(arr)
      unless arr.is_a?(Array) && arr.length == 21
        raise InvalidParametersError, "parameters must be exactly 21 weights, got #{arr.inspect}"
      end
      weights = arr.each_with_index.map { |w, i| real(w, "weight[#{i}]") }
      Parameters.clip(weights)
    rescue ValidationError => e
      raise InvalidParametersError, e.message
    end

    def memory(ms)
      raise ValidationError, "memory_state must be a FsrsCore::MemoryState, got #{ms.inspect}" unless ms.is_a?(MemoryState)
      [stability(ms.stability), difficulty(ms.difficulty)]
    end

    def stability(s)
      v = real(s, "stability")
      raise ValidationError, "stability must be in [0.001, 36500], got #{s.inspect}" unless v >= 0.001 && v <= 36_500.0
      v
    end

    def difficulty(d)
      v = real(d, "difficulty")
      raise ValidationError, "difficulty must be in [1.0, 10.0], got #{d.inspect}" unless v >= 1.0 && v <= 10.0
      v
    end

    def fractional_days(x)
      v = real(x, "days_elapsed")
      raise ValidationError, "days_elapsed must be >= 0, got #{x.inspect}" unless v >= 0.0
      v
    end

    def u32(n, name)
      unless n.is_a?(Integer) && n >= 0 && n <= U32_MAX
        raise ValidationError, "#{name} must be an Integer in 0..#{U32_MAX}, got #{n.inspect}"
      end
      n
    end

    def rating(r)
      unless r.is_a?(Integer) && r >= 1 && r <= 4
        raise ValidationError, "rating must be an Integer in 1..4, got #{r.inspect}"
      end
      r
    end

    def reviews(arr)
      raise ValidationError, "reviews must be a non-empty Array, got #{arr.inspect}" unless arr.is_a?(Array) && !arr.empty?
      ratings = []
      deltas = []
      arr.each_with_index do |rv, i|
        raise ValidationError, "reviews[#{i}] must be a FsrsCore::Review" unless rv.is_a?(Review)
        ratings << rating(rv.rating)
        d = u32(rv.delta_t, "reviews[#{i}].delta_t")
        raise ValidationError, "reviews[0].delta_t must be 0, got #{d}" if i.zero? && d != 0
        deltas << d
      end
      [ratings, deltas]
    end
  end
end
