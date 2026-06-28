# frozen_string_literal: true
module FsrsCore
  MemoryState = Data.define(:stability, :difficulty)
  ItemState   = Data.define(:memory, :interval)
  NextStates  = Data.define(:again, :hard, :good, :easy)
  Review      = Data.define(:rating, :delta_t)
end
