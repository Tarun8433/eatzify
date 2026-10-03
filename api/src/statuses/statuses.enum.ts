export enum StatusEnum {
  active = 1,
  inactive = 2,
  /// Admin panel plan, Phase A: an admin blocked the account. Sign-in and every token refuse it
  /// until the block is lifted or expires (`user_block`).
  blocked = 3,
}
