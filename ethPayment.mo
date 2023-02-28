import Principal "mo:base/Principal";
import Trie "mo:base/Trie";
import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Buffer "mo:base/Buffer";
import Char "mo:base/Char";
import Iter "mo:base/Iter";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Text "mo:base/Text";
import Cycles "mo:base/ExperimentalCycles";
import Blob "mo:base/Blob";
import Result "mo:base/Result";

actor ethPayment {

  //Using Etherscan only for prototype
  //Receiver address is where you want the payments

  let receiverAddress = "0x714a1A2960a17cB101A2d55C21d1D84441f2a5A3";

  //Store users send codes 
  stable var userDecimalIds : Trie.Trie<Principal, Nat> = Trie.empty();

  //First decimal id is high to allow 'easy' copypaste to metamask, negligible amount of eth. too many consecutive 0s might drop the last decimals when pasting to metamask.
  stable var currentNextDecimal : Nat = 10020030001;

  //Lock the Principal while calling functions
  let locksDB = Buffer.Buffer<Principal>(5);

  //Tx hashes that have been claimed
  stable var usedTxHashes : Trie.Trie<Text, Bool> = Trie.empty();


  public shared(msg) func getSendInfo(sendAmountInThousandths : Nat) : async (Text, Text){
    //Allocates a lowest decimal for caller. 18 decimals in ethereum tokens allow for millions of users to without it really affecting the cost.
    let caller = msg.caller;

    //Prototype only for under 1eth tx
    if (sendAmountInThousandths > 999){
      return ("invalid amount", "send amount 1-999 eth thousandths");
    };

    //Validate and lock the user, else fail
    let validUser = validateAndLock(caller);
    switch(validUser){
      case(2){};
      case(default){return ("nope", "error")};
    };
    var userDecimalId = 0;

    switch(Trie.get(userDecimalIds, key(caller), Principal.equal)){
      case(null){
        //Create new decimalId for caller
        userDecimalId := currentNextDecimal;
        userDecimalIds := Trie.put(userDecimalIds, key(caller), Principal.equal, userDecimalId).0;
        currentNextDecimal += 1;
      };
      case(?decimalId){
        //Get decimalId of user
        userDecimalId := decimalId;
      };
    };

    //Get the eth wei amount with smallest decimal coding
    //Offer the copypasteable text as eth amount
    var sendAmountText = "Something is wrong";
    let amountToSend = (Nat.pow(10, 14) * sendAmountInThousandths) + userDecimalId;
    let textAmount = Nat.toText(amountToSend);

    switch(Text.size(Nat.toText(sendAmountInThousandths))){
      case(1){sendAmountText := "0.00" # textAmount};
      case(2){sendAmountText := "0.0" # textAmount};
      case(3){sendAmountText := "0." # textAmount};
      case(default){sendAmountText := "something went wrong"};
    };
    //Unlocks the user and checks its succesful
    let unlocked = unlockUser(caller); 
    assert(unlocked);

    //Decimal coding saved for user, now they need to send the specified amount to eth address, wait for block confirmations and call confirmTx
    return (sendAmountText, receiverAddress);
  };


  public shared(msg) func confirmTx(redeemAmount : Nat, txHash : Text) : async Result.Result<[Bool], Text>{
    //Redeem amount in 1/1000s of eth
    //Https outcall to etherscan for the txHash
    let caller = msg.caller;
    
    //Lock and validate the user
    let validUser = validateAndLock(caller);
    switch(validUser){
      case(1){return #err("anonymous principal")};
      case(2){};
      case(3){return #err("user already locked")};
      case(default){};
    };
    
    switch(Trie.get(usedTxHashes, keyText(txHash), Text.equal)){
      case(null){};
      case(?used){return #err("tx hash consumed already")}
    };
    
    //Get users decimalId, 
    var userDecimalId = 0;
    switch(Trie.get(userDecimalIds, key(caller), Principal.equal)){
      case(null){
        return #err("Reserve a decimal coder first");
      };
      case(?decimal){
        userDecimalId := decimal;
      };
    };

    let redeemInWei = (Nat.pow(10, 14) * redeemAmount) + userDecimalId;

    let ic : IC = actor ("aaaaa-aa");
    let fullTxUrl = "https://etherscan.io/tx/" # txHash;
    
    //Get etherscan tx page
      let requestTxEtherscan : CanisterHttpRequestArgs = {
        url = fullTxUrl;
        max_response_bytes = ?80000; 
        headers = [];
        body = null;
        method = #get;
        transform = ?transform_etherscan;
      };
      //Could be lower, ~$0.01.
      Cycles.add(10_000_000_000);

      let responseTx : CanisterHttpResponsePayload = await ic.http_request(requestTxEtherscan);
      let bodyAsTextEtherscan = decode(responseTx);

      let confirmedTxEtherscan = Text.contains(bodyAsTextEtherscan, #text("adge bg-success bg-opacity-10 border border-success border-opacity-25"));      
      let correctAmountEtherscan = Text.contains(bodyAsTextEtherscan, #text((Nat.toText(redeemInWei))));
      let correctReceiverEtherscan = Text.contains(bodyAsTextEtherscan, #text(receiverAddress));
      let emptyTxData = Text.contains(bodyAsTextEtherscan, #text("0x</textarea><span id='rawinput' style='display:none' '>0x</s"));

      let allOk = ([confirmedTxEtherscan, correctAmountEtherscan, correctReceiverEtherscan, emptyTxData,]);
      usedTxHashes := Trie.put(usedTxHashes, keyText(txHash), Text.equal, true).0;

    //Unlocks the user and checks its succesful
    let unlocked = unlockUser(caller); 
    assert(unlocked);

    //[receiverAddresOk, sendAmountOk, TxHashOk, BlockConfirmationsOk]
    return #ok(allOk);
  };


  func decode(response : CanisterHttpResponsePayload) : Text{
    //Decode [Nat8] to text
    let textBody = Array.foldRight<Nat8, Text>(
      response.body,
      "",
      func(x, acc) = Char.toText(Char.fromNat32(Nat32.fromNat(Nat8.toNat(x)))) # acc
    );
    return textBody;
  };

  func encode(htmlText : Text) : [Nat8]{
    //Encode text to [Nat8]
    let buffer = Buffer.Buffer<Nat8>(20);
    for(character in htmlText.chars()){
      buffer.add(Nat8.fromNat(Nat32.toNat(Char.toNat32(character))));
    };
    return Buffer.toArray<Nat8>(buffer);
  };

  //Trie key generators
  func key(x : Principal) : Trie.Key<Principal> {
    return { hash = Principal.hash(x); key = x };
  };
  func keyText(x : Text) : Trie.Key<Text> {
    return { hash = Text.hash(x); key = x };
  };


  func validateAndLock(user : Principal) : Nat{
    //Check user is not anon and not already locked. 
    if(Principal.isAnonymous(user)){
      return 1;
    };
    switch(Buffer.indexOf(user, locksDB, Principal.equal)){
      case(null){ 
        //Locks user
        locksDB.add(user);
        return 2;
        };
      case(?indexAt){ 
        //User already locked
        return 3 };
    };
  };


  func unlockUser(user : Principal) : Bool{
    switch(Buffer.indexOf(user, locksDB, Principal.equal)){
      case(null){ 
        //User is not locked, should not be possible
        return false;
        };
      case(?indexAt){ 
        //Remove user lock
        ignore locksDB.remove(indexAt);
        return true; 
        };
    };
  };


 public query func transformEtherscan(raw : TransformArgs) : async CanisterHttpResponsePayload {
    var bodyWorker = Buffer.Buffer<Nat8>(20);
    let bufferBody = Buffer.fromArray<Nat8>(raw.response.body);
    //Transform page to only contain important parts, to save on cycles and help creating consensus for https outcall
    
    //These can be checked with simple isStrictSubBufferOf
    //Cross check that the other sources dont contain this rawinput data, to prevent tx data manipulation
    let rawInput : [Nat8] = encode("0x</textarea><span id='rawinput' style='display:none' '>0x</s");
    let inputBuffer = Buffer.fromArray<Nat8>(rawInput);
    
    let receiver : [Nat8] = encode(receiverAddress);
    let receiverBuffer = Buffer.fromArray<Nat8>(receiver);
    
    let successfulTx : [Nat8] = encode("adge bg-success bg-opacity-10 border border-success border-opacity-25");
    let successfulBuffer = Buffer.fromArray<Nat8>(successfulTx);
    
    //Get the data
    if(Buffer.isStrictSubBufferOf<Nat8>(inputBuffer, bufferBody, Nat8.equal)){
      bodyWorker.append(inputBuffer);
    };
    if(Buffer.isStrictSubBufferOf<Nat8>(receiverBuffer, bufferBody, Nat8.equal)){
      bodyWorker.append(receiverBuffer);
    };
    if(Buffer.isStrictSubBufferOf<Nat8>(successfulBuffer, bufferBody, Nat8.equal)){
      bodyWorker.append(successfulBuffer);
    };

    //These need extra attention to get the important data without messing consensus (For example, 20 chars more would catch the current eth price)
    //Amount ends where "amount" starts
    let amount : [Nat8]= encode("ETH to be transferred to the recipient with the transaction'>0<b>.</b>");
    let amountBuffer = Buffer.fromArray<Nat8>(amount);

    //Get the sent amount data
    switch(Buffer.indexOfBuffer<Nat8>(amountBuffer,bufferBody, Nat8.equal)){
      case(null){};
      case(?index){
        let newBuffer = Buffer.Buffer<Nat8>(100);
        for(x in Iter.range(index, index+98)){
          newBuffer.add(bufferBody.get(x));
        };
        bodyWorker.append(newBuffer);
      };
    };
  
    let transformed : CanisterHttpResponsePayload = {
        status = 0;
        body = Buffer.toArray(bodyWorker);
        headers = [];
    };
    transformed;
  };

  let transform_etherscan : TransformContext = {
      function = transformEtherscan;
      context = Blob.fromArray([]);
  };

  //Not used
  public query func transform(raw : TransformArgs) : async CanisterHttpResponsePayload {
        let transformed : CanisterHttpResponsePayload = {
            status = raw.response.status;
            body = raw.response.body;
            headers = [];
        };
        transformed;
    };
    let transform_context : TransformContext = {
        function = transform;
        context = Blob.fromArray([]);
    };


    public type HttpHeader = {
        name : Text;
        value : Text;
    };

    public type HttpMethod = {
        #get;
        #post;
        #head;
    };

    public type TransformContext = {
        function : shared query TransformArgs -> async CanisterHttpResponsePayload;
        context : Blob;
    };

    public type CanisterHttpRequestArgs = {
        url : Text;
        max_response_bytes : ?Nat64;
        headers : [HttpHeader];
        body : ?[Nat8];
        method : HttpMethod;
        transform : ?TransformContext;
    };

    public type CanisterHttpResponsePayload = {
        status : Nat;
        headers : [HttpHeader];
        body : [Nat8];
    };

    public type CanisterHttpResponsePayloadDecoded = {
        status : Nat;
        headers : [HttpHeader];
        body : Text;
    };

    public type TransformArgs = {
        response : CanisterHttpResponsePayload;
        context : Blob;
    };

    public type IC = actor {
        http_request : CanisterHttpRequestArgs -> async CanisterHttpResponsePayload;
    };

};
