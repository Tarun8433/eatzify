/**
 * A contact card for one person.
 *
 * Built in the browser from data already on screen rather than fetched from a new endpoint: the
 * record is open and audited, and a second round trip would add a second audit row for the same
 * read. Downloading it is a local act — nothing leaves the machine.
 *
 * `NOTE` carries where the number came from, because a number saved to a phone with no context is
 * how a client's number ends up being used for something the client never consented to.
 */
export function buildVCard(input: {
  name: string;
  phone: string;
  email?: string | null;
  note?: string;
}): string {
  // CRLF and the exact field order are the spec's, not a preference — some address books refuse a
  // card that uses bare newlines.
  const escape = (v: string) => v.replace(/([,;\\])/g, '\\$1').replace(/\n/g, '\\n');

  const lines = [
    'BEGIN:VCARD',
    'VERSION:3.0',
    `FN:${escape(input.name)}`,
    `N:${escape(input.name)};;;;`,
    `TEL;TYPE=CELL:${escape(input.phone)}`,
  ];

  if (input.email) lines.push(`EMAIL;TYPE=INTERNET:${escape(input.email)}`);
  if (input.note) lines.push(`NOTE:${escape(input.note)}`);

  lines.push('END:VCARD');
  return lines.join('\r\n');
}

/// Hand the card to the browser as a download. Revokes the object URL straight after — a blob URL
/// left alive pins the data in memory for the life of the tab.
export function downloadVCard(filename: string, vcard: string): void {
  const url = URL.createObjectURL(new Blob([vcard], { type: 'text/vcard;charset=utf-8' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
