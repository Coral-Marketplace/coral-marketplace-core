const { expect, assert } = require('chai');

describe('************ NFT ******************', ()  => {
  let nft, nftContractAddress, contractOwner, artist, creator, token1Id, token2Id, 
    royaltyValue, newTokenURI, salePrice, creatorAddress, artistAddress;

  before(async () => {
    // Deployed contract address (comment to deploy new contract)
    nftContractAddress = config.contracts.nft;

    // Get accounts
    contractOwner = await reef.getSignerByName('account1');
    creator = await reef.getSignerByName('account2');
    artist = await reef.getSignerByName('account3');

    // Get accounts addresses
    creatorAddress = await creator.getAddress();
    artistAddress = await artist.getAddress();

    // Initialize global variables
    newTokenURI = 'https://fake-uri-xyz.com';
    salePrice = ethers.utils.parseUnits('50', 'ether');
    royaltyValue = 1000; // 10%
    
    if (!nftContractAddress) {
      // Deploy CoralNFT contract
      console.log('\tdeploying NFT contract...');
      const NFT = await reef.getContractFactory('CoralNFT', contractOwner);
      nft = await NFT.deploy('0x0000000000000000000000000000000000000000', 
        '0x0000000000000000000000000000000000000000');
      await nft.deployed();
      nftContractAddress = nft.address;
    } else {
      // Get deployed contract
      const NFT = await reef.getContractFactory('CoralNFT', contractOwner);
      nft = await NFT.attach(nftContractAddress);
    }
    console.log(`\tNFT contact deployed ${nftContractAddress}`);
  });


  it('Should get NFT contract data', async () => {
    const name = await nft.name();
    const interfaceIdErc2981 = '0x2a55205a';
    const supportsErc2981 = await nft.supportsInterface(interfaceIdErc2981);

    expect(name).to.equal('Coral NFT');
    expect(supportsErc2981).to.equal(true);
  });


  it('Should create NFTs', async () => {
    // Create NFTs
    console.log('\tcreating NFTs...');

    const tx1 = await nft.connect(creator).createToken('https://fake-uri-1.com', artistAddress, royaltyValue, false);
    const receipt1 = await tx1.wait();
		token1Id = receipt1.events[0].args[2].toNumber();

    const tx2 = await nft.connect(creator).createToken('https://fake-uri-2.com', artistAddress, royaltyValue, true);
    const receipt2 = await tx2.wait();
		token2Id = receipt2.events[0].args[2].toNumber();

    console.log(`\tNFTs created with tokenIds ${token1Id} and ${token2Id}`);

    // End data
    const royaltyInfo = await nft.royaltyInfo(token1Id, salePrice);

    // Evaluate results
    expect(royaltyInfo.receiver).to.equal(artistAddress);
    expect(Number(royaltyInfo.royaltyAmount)).to.equal(salePrice * royaltyValue / 10000);
    expect(await nft.ownerOf(token1Id)).to.equal(creatorAddress);
    expect(await nft.tokenURI(token1Id)).to.equal('https://fake-uri-1.com');
    expect(await nft.hasMutableURI(token1Id)).to.equal(false);
    expect(await nft.hasMutableURI(token2Id)).to.equal(true);
  });


  it('Should not change tokenURI for immutable token', async () => {
    // Change tokenURI
    console.log('\tcreator changing tokenURI...');
    await throwsException(nft.connect(creator).setTokenURI(token1Id, newTokenURI),
      'CoralNFT: The metadata of this token is immutable.');
  });


  it('Should not change tokenURI if caller is not ower of the token', async () => {
    // Change tokenURI
    console.log('\tcontract owner changing tokenURI...');
    await throwsException(nft.connect(contractOwner).setTokenURI(token1Id, newTokenURI),
      'CoralNFT: Only token owner can set tokenURI.');
  });


  it('Should change tokenURI', async () => {
    // Initial data
    const iniTokenURI = await nft.tokenURI(token2Id);

    // Change tokenURI
    console.log('\tcreator changing tokenURI...');
    await nft.connect(creator).setTokenURI(token2Id, newTokenURI);
    console.log('\ttokenURI changed.');

    // Final data
    const endTokenURI = await nft.tokenURI(token2Id);

    expect(endTokenURI).to.not.equal(iniTokenURI);
    expect(endTokenURI).to.equal(newTokenURI);
  });


  async function throwsException(promise, message) {
    try {
      await promise;
      assert(false);
    } catch (error) {
      expect(error.message).contains(message);
    }
  };

});
