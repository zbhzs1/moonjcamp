///|
extern "js" fn request() -> String =
  #| () => globalThis.__moonjcamp_request

///|
extern "js" fn respond(text : String) -> Unit =
  #| text => { globalThis.__moonjcamp_response = text; }

///|
fn main {
  respond(@jcamp.protocol(request()))
}
