module.exports = {
  title: "shell execute config options"
  type: "object"
  properties:
    sequential:
      description: "
        Run all shell commands sequential (not in parallel). Enable this if you have commands 
        that should not be execute in parallel
      "
      type: "boolean"
      default: false
}