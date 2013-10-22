D Implementation of the Expect framework (http://expect.sourceforge.net/)

TODOs:
   -> The Before and After properties dont behave very well. Need to implement a fix to these.
   -> Implement an expect(string[] toExpect) method, that returns an int representing the index of the array which was matched.
      This will allow int idx = expect(["password:", "username:"]); constructs to handle multiple cases in one expect call.
   -> Properly test, and write unittests to be sure it all works correctly for edge cases.

