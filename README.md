D Implementation of the Expect framework (http://expect.sourceforge.net/)

Currently *nix only, though will look into writing it for windows aswell.

TODOs:

-> Implement an expect(string[] toExpect) method, that returns an int representing the index of the array which was matched.
   This will allow int idx = expect(["password:", "username:"]); constructs to handle multiple cases in one expect call.
    
-> Properly test, and write unittests to be sure it all works correctly for edge cases.

-> Look into supporting Windows.
