/** @type {import('next').NextConfig} */
module.exports = {
  reactStrictMode: true,
  // The dashboard shows employee photos from the API's file store and, in development, from
  // Unsplash. Anything else is refused rather than allowed by a wildcard.
  images: { remotePatterns: [{ protocol: 'https', hostname: 'images.unsplash.com' }] },
};
