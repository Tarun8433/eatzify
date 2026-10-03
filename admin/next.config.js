/** @type {import('next').NextConfig} */
module.exports = {
  reactStrictMode: true,
  // A self-contained server for the Docker image (admin panel plan, Phase A hosting).
  output: 'standalone',
  // The dashboard shows employee photos from the API's file store and, in development, from
  // Unsplash. Anything else is refused rather than allowed by a wildcard.
  images: { remotePatterns: [{ protocol: 'https', hostname: 'images.unsplash.com' }] },
};
