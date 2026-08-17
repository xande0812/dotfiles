dotenvx() {
  DOTENV_PRIVATE_KEY="$(op read 'op://Private/vqk3xwgjcarejycen7ms3meyva/DOTENV_PRIVATE_KEY')" command dotenvx "$@"
}
