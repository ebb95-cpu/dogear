import type { Config } from "tailwindcss";
const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      fontFamily: { serif: ['"Iowan Old Style"', "Georgia", "serif"] },
    },
  },
  plugins: [],
};
export default config;
