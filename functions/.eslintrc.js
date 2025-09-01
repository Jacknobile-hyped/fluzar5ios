module.exports = {
  root: true,
  env: {
    es6: true,
    node: true,
  },
  extends: [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
  ],
  parser: "@typescript-eslint/parser",
  parserOptions: {
    sourceType: "module",
  },
  plugins: [
    "@typescript-eslint"
  ],
  rules: {
    "@typescript-eslint/no-explicit-any": "warn",
    "max-len": "off",
    "quotes": "off",
    "object-curly-spacing": "off",
    "indent": "off",
    "linebreak-style": "off"
  },
  ignorePatterns: ["lib/**/*", "*.js"]
};