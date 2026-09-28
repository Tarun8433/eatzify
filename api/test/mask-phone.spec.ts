import { maskPhone } from '../src/admin/admin-clients.service';

/// docs/13 §4: "full phone + email visible in admin list views → mask by default, reveal on an
/// audited action". A list has to stay scannable, so the mask keeps the two parts a human uses to
/// recognise a number they already know, and drops the part that makes it dialable.
describe('masking a phone number for a list view', () => {
  it('should keep the country code and the last four digits', () => {
    expect(maskPhone('+919933938833')).toBe('+919…8833');
  });

  it('should not leak the middle digits that make a number dialable', () => {
    const masked = maskPhone('+919933938833');
    expect(masked).not.toContain('3393');
    expect(masked!.replace(/\D/g, '').length).toBeLessThan(
      '+919933938833'.replace(/\D/g, '').length,
    );
  });

  it('should return null when there is no number rather than a fake mask', () => {
    expect(maskPhone(null)).toBeNull();
  });

  it('should hide a number too short to mask meaningfully', () => {
    // Masking "12345" as "+123…2345" would invent digits and overlap the halves.
    expect(maskPhone('12345')).toBe('••••');
  });
});
