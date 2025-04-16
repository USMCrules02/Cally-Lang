# About Cally-Lang
Dont like pythons white space but like its readability and easy of use.<br/>
Well look no further Cally Lang is here.<br/>
Cally-Lang is a great alternative if you don't care about performace, since the interpreter is written entirely in Powershell 7.4 (Compatible with 5.4 => lower version might not function properly).<br/>
Why Powershell?<br/>
![360_F_166100342_KbTGIRrnrlwGDZSXSMpH3zfn2dxyTKae](https://github.com/user-attachments/assets/5c8e4128-cc89-480e-9142-820d99d6366d)<br/>

# Running Cally-Lang<br/>
Parameters:<br/>
  - Switch flags:<br/>
    -ast : Outputs the AST (in JSON format).<br/>
    -ts  : Outputs the token stream.<br/>
  - args:<br/>
    additional aguments you would want to add on start up<br/>
Usage:<br/>
clc.ps1 <Path_To_Your_Program.clp> <args> [-ast] [-ts] <br/>
Note: additional arguments can single arguments or multiple aguments <br/>
Example without arguments or switchs: clc.ps1 my_program.clp <br/>
Example with 1 argument and both switchs flags: clc.ps1 my_program.clp 1234 -ast -ts <br/>
Example with many argument: clc.ps1 my_program.clp 1 2 3 4 -ast -ts <br/>
## Initialization Syntax<br/>
// comments are signified by a double slash<br/>
// Example With optional aguments<br/>
Main(args){<br/>
// Code<br/>
}<br/>
Main {<br/>
// Code<br/>
}<br/>
## Using args<br/>
// With 1 argument <br/>
// passed args Hello <br/>
Main(args){<br/>
  print(args) // Output is Hello<br/>
}<br/>
// With many argument and a custom name for args<br/>
// passed args: 1 2 3 4<br/>
Main(valuesPassed){<br/>
  print(valuesPassed[0]) // output is 1<br/>
}<br/><br/>

Note: a semicolon is required at the end of all varible declarations, builtin functions(print, len, input), assignment operations, and mathmatical operations.<br/>
## Varible Syntax<br/>
string_Example = "Hello";<br/>
int_Example = 1234;<br/>
array_Example = [1,2,3,4];<br/>
object_Example = { name: "Bob" , age: 30 };<br/>
## Print and Input Operator Syntax<br/>
name = input("What is your name: "); // Prompts can be added to input function <br/>
age = input("What is your age: "); <br/>
print("Name: " + name + "\n"); // '\n' is the new line character in this language <br/> 
print("Age: " age "\n") // This also works and is required when using integers <br/> 
## Length Operator Syntax<br/>
val = "abcd";<br/>
arr = [1,2];<br/>
len(val); // Result would be 4<br/>
len(arr); // Result would be 2<br/>
## For Loop Syntax<br/>
for(i=0; i < 10; i++){<br/>
// Code<br/>
}<br/>
// You can also use variables<br/>
b = 5;<br/>
for(i=0; i <= b; i++){<br/>
// Code<br/>
}<br/>
## While Loop Syntax<br/>
i = 0<br/>
while(i < 10){<br/> // You are also able to use only varible here<br/>
// Code<br/>
 i++;<br/>
}<br/>
## Supported Operations<br/>
Cally‑Lang supports the following math and comparison operations:<br/>
- **Addition:** `+`  <br/>
  *Example:* `3 + 4` returns 7.<br/>
- **Subtraction:** `-`  <br/>
  *Example:* `10 - 2` returns 8.<br/>
- **Multiplication:** `*`  <br/>
  *Example:* `5 * 6` returns 30.<br/>
- **Division:** `/`  <br/>
  *Example:* `20 / 4` returns 5 (integer division).<br/>
- **Modulus:** `%`  <br/>
  *Example:* `20 % 3` returns 2.<br/>
- **Equality:** `==`  <br/>
  *Example:* `5 == 5` returns true.<br/>
- **Inequality:** `!=`  <br/>
  *Example:* `5 != 2` returns true.<br/>
- **Less than:** `<`  <br/>
  *Example:* `3 < 5` returns true.<br/>
- **Less than or equal to:** `<=`  <br/>
  *Example:* `3 <= 3` returns true.<br/>
- **Greater than:** `>`  <br/>
  *Example:* `7 > 5` returns true.<br/>
- **Greater than or equal to:** `>=`  <br/>
  *Example:* `7 >= 7` returns true.<br/>
- **Post-increment:** `++`  <br/>
  *Example:* `i++` increments `i` after its current value is used.<br/>
- **Post-decrement:** `--`  <br/>
  *Example:* `i--` decrements `i` after its current value is used.<br/>




