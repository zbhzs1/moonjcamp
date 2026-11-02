///|
extern "js" fn request() -> String =
  #| () => globalThis.__moonjcamp_request

///|
fn main {
  println(@jcamp.protocol(request()))
}
