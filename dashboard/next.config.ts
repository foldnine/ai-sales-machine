import type { NextConfig } from "next";

const config: NextConfig = {
  // One self-contained server in the Docker image (Dockerfile).
  output: "standalone",
  poweredByHeader: false,
  reactStrictMode: true,
};

export default config;
