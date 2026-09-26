/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,jsx}"],
  theme: {
    extend: {
      colors: {
        canvas: "#F6F5F1",
        ink: "#1F2320",
        panel: "#FFFFFF",
        line: "#E4E1D8",
        brand: {
          DEFAULT: "#2F5233",
          dark: "#1F3A23",
          light: "#3F6B45",
        },
        amber: {
          DEFAULT: "#C97B2E",
          light: "#F1DDBE",
        },
        status: {
          draft: "#8A8F87",
          waiting: "#C97B2E",
          ready: "#3B6FA0",
          done: "#2F5233",
          cancelled: "#B23A2E",
        },
        charcoal: "#20241F",
      },
      fontFamily: {
        display: ["'Space Grotesk'", "sans-serif"],
        body: ["'Inter'", "sans-serif"],
      },
    },
  },
  plugins: [],
}
