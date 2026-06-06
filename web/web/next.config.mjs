/** @type {import('next').NextConfig} */
const configuredBasePath = process.env.NEXT_PUBLIC_BASE_PATH ?? "";
const basePath =
  configuredBasePath && configuredBasePath !== "/"
    ? configuredBasePath.startsWith("/")
      ? configuredBasePath
      : `/${configuredBasePath}`
    : "";

const nextConfig = {
  transpilePackages: ["@drive-ride/shared"],
  ...(basePath ? { basePath } : {})
};

export default nextConfig;
