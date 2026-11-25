/// "1 album", "18 albums": English nouns that take a plain "s".
public func pluralized(_ number: Int, _ noun: String) -> String {
    "\(number) \(number == 1 ? noun : noun + "s")"
}
