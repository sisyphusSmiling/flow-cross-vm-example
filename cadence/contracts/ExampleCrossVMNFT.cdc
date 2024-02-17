/* 
*
*  This is an example implementation of a Flow Non-Fungible Token
*  using the V2 standard.
*  It is not part of the official standard but it assumed to be
*  similar to how many NFTs would implement the core functionality.
*
*  This contract does not implement any sophisticated classification
*  system for its NFTs. It defines a simple NFT with minimal metadata.
*   
*/

import "NonFungibleToken"
import "ViewResolver"
import "MetadataViews"
import "FungibleToken"
import "FlowToken"

import "EVM"

import "ICrossVM"
import "CrossVMNFT"
import "IFlowEVMNFTBridge"
import "IEVMBridgeNFTLocker"
import "FlowEVMBridgeUtils"

access(all) contract ExampleCrossVMNFT: NonFungibleToken, ICrossVM, IFlowEVMNFTBridge, IEVMBridgeNFTLocker {

    /// Type of NFT locked in the contract
    access(all) let lockedNFTType: Type
    /// The address of the EVM contract targetted by this bridge. Defines the NFT being bridged in Flow EVM
    access(all) let evmNFTContractAddress: EVM.EVMAddress
    /// The address of the Flow contract targetted by this bridge. Defines the NFT being bridged in Flow
    /// In this case, the NFT-defining contract is its own bridge contract
    access(all) let flowNFTContractAddress: Address
    // Fee to bridge an NFT
    access(self) var bridgingFee: UFix64
    access(contract) let locker: @{CrossVMNFT.EVMNFTCollection, NonFungibleToken.Collection}

    /// Path where the minter should be stored
    /// The standard paths for the collection are stored in the collection resource type
    access(all) let MinterStoragePath: StoragePath

    /// We choose the name NFT here, but this type can have any name now
    /// because the interface does not require it to have a specific name any more
    access(all) resource NFT: CrossVMNFT.EVMNFT {

        access(all) let id: UInt64
        access(all) let evmID: UInt256
        access(all) let symbol: String

        /// From the Display metadata view
        access(all) let name: String
        access(all) let description: String
        access(all) let thumbnail: String

        /// For the Royalties metadata view
        access(self) let royalties: [MetadataViews.Royalty]

        /// Generic dictionary of traits the NFT has
        access(self) let metadata: {String: AnyStruct}
    
        init(
            name: String,
            evmID: UInt256,
            symbol: String,
            description: String,
            thumbnail: String,
            royalties: [MetadataViews.Royalty],
            metadata: {String: AnyStruct},
        ) {
            self.id = self.uuid
            self.name = name
            self.evmID = evmID
            self.symbol = symbol
            self.description = description
            self.thumbnail = thumbnail
            self.royalties = royalties
            self.metadata = metadata
        }

        /// createEmptyCollection creates an empty Collection
        /// and returns it to the caller so that they can own NFTs
        /// @{NonFungibleToken.Collection}
        access(all) fun createEmptyCollection(): @{NonFungibleToken.Collection} {
            return <-ExampleCrossVMNFT.createEmptyCollection(nftType: Type<@ExampleCrossVMNFT.NFT>())
        }
    
        access(all) view fun getViews(): [Type] {
            return [
                Type<MetadataViews.Display>(),
                Type<MetadataViews.Royalties>(),
                Type<MetadataViews.Editions>(),
                Type<MetadataViews.ExternalURL>(),
                Type<MetadataViews.NFTCollectionData>(),
                Type<MetadataViews.NFTCollectionDisplay>(),
                Type<MetadataViews.Serial>(),
                Type<MetadataViews.Traits>()
            ]
        }

        access(all) fun resolveView(_ view: Type): AnyStruct? {
            switch view {
                case Type<MetadataViews.Display>():
                    return MetadataViews.Display(
                        name: self.name,
                        description: self.description,
                        thumbnail: MetadataViews.HTTPFile(
                            url: self.thumbnail
                        )
                    )
                case Type<MetadataViews.Editions>():
                    // There is no max number of NFTs that can be minted from this contract
                    // so the max edition field value is set to nil
                    let editionInfo = MetadataViews.Edition(name: "Example NFT Edition", number: self.id, max: nil)
                    let editionList: [MetadataViews.Edition] = [editionInfo]
                    return MetadataViews.Editions(
                        editionList
                    )
                case Type<MetadataViews.Serial>():
                    return MetadataViews.Serial(
                        self.id
                    )
                case Type<MetadataViews.Royalties>():
                    return MetadataViews.Royalties(
                        self.royalties
                    )
                case Type<MetadataViews.ExternalURL>():
                    return MetadataViews.ExternalURL("https://example-nft.onflow.org/".concat(self.id.toString()))
                case Type<MetadataViews.NFTCollectionData>():
                    return ExampleCrossVMNFT.resolveContractView(resourceType: Type<@ExampleCrossVMNFT.NFT>(), viewType: Type<MetadataViews.NFTCollectionData>())
                case Type<MetadataViews.NFTCollectionDisplay>():
                    return ExampleCrossVMNFT.resolveContractView(resourceType: Type<@ExampleCrossVMNFT.NFT>(), viewType: Type<MetadataViews.NFTCollectionDisplay>())
                case Type<MetadataViews.Traits>():
                    // exclude mintedTime and foo to show other uses of Traits
                    let excludedTraits = ["mintedTime", "foo"]
                    let traitsView = MetadataViews.dictToTraits(dict: self.metadata, excludedNames: excludedTraits)

                    // mintedTime is a unix timestamp, we should mark it with a displayType so platforms know how to show it.
                    let mintedTimeTrait = MetadataViews.Trait(name: "mintedTime", value: self.metadata["mintedTime"]!, displayType: "Date", rarity: nil)
                    traitsView.addTrait(mintedTimeTrait)

                    // foo is a trait with its own rarity
                    let fooTraitRarity = MetadataViews.Rarity(score: 10.0, max: 100.0, description: "Common")
                    let fooTrait = MetadataViews.Trait(name: "foo", value: self.metadata["foo"], displayType: nil, rarity: fooTraitRarity)
                    traitsView.addTrait(fooTrait)
                    
                    return traitsView
            }
            return nil
        }

        access(all) fun tokenURI(): String {
            // TODO: Consider adding this field to EVMNFT interface
            return ""
        }

        access(all) fun getEVMContractAddress(): EVM.EVMAddress {
            return ExampleCrossVMNFT.getEVMContractAddress()
        }

        /// Returns the address of the bridge contract host
        access(all) view fun getDefaultBridgeAddress(): Address {
            return ExampleCrossVMNFT.account.address
        }
        /// Returns a reference to a contract as `&AnyStruct`. This enables the result to be cast as a bridging
        /// contract by the caller and avoids circular dependency in the implementing contract
        access(all) view fun borrowDefaultBridgeContract(): &AnyStruct {
            return &ExampleCrossVMNFT
        }
    }

    access(all) resource Collection: CrossVMNFT.EVMNFTCollection {
        /// dictionary of NFT conforming tokens
        /// NFT is a resource type with an `UInt64` ID field
        access(contract) var ownedNFTs: @{UInt64: ExampleCrossVMNFT.NFT}
        access(contract) var evmIDToFlowID: {UInt256: UInt64}

        access(all) var storagePath: StoragePath
        access(all) var publicPath: PublicPath

        init () {
            self.ownedNFTs <- {}
            self.evmIDToFlowID = {}
            let identifier = "exampleCrossVMNFTCollection"
            self.storagePath = StoragePath(identifier: identifier)!
            self.publicPath = PublicPath(identifier: identifier)!
        }

        /// getSupportedNFTTypes returns a list of NFT types that this receiver accepts
        access(all) view fun getSupportedNFTTypes(): {Type: Bool} {
            return { Type<@ExampleCrossVMNFT.NFT>(): true }
        }

        /// Returns whether or not the given type is accepted by the collection
        /// A collection that can accept any type should just return true by default
        access(all) view fun isSupportedNFTType(type: Type): Bool {
            return self.getSupportedNFTTypes()[type] ?? false
        }

        /// withdraw removes an NFT from the collection and moves it to the caller
        access(NonFungibleToken.Withdrawable) fun withdraw(withdrawID: UInt64): @{NonFungibleToken.NFT} {
            let token <- self.ownedNFTs.remove(key: withdrawID)
                ?? panic("Could not withdraw an NFT with the provided ID from the collection")
            self.evmIDToFlowID.remove(key: token.evmID)
            return <-token
        }

        /// deposit takes a NFT and adds it to the collections dictionary
        /// and adds the ID to the id array
        access(all) fun deposit(token: @{NonFungibleToken.NFT}) {
            let token <- token as! @ExampleCrossVMNFT.NFT
            self.evmIDToFlowID[token.evmID] = token.id

            // add the new token to the dictionary which removes the old one
            let oldToken <- self.ownedNFTs[token.id] <- token

            destroy oldToken
        }

        /// getIDs returns an array of the IDs that are in the collection
        access(all) view fun getIDs(): [UInt64] {
            return self.ownedNFTs.keys
        }

        access(all) view fun getEVMIDs(): [UInt256] {
            return self.evmIDToFlowID.keys
        }
        access(all) view fun getFlowID(from evmID: UInt256): UInt64? {
            return self.evmIDToFlowID[evmID]
        }

        /// Gets the amount of NFTs stored in the collection
        access(all) view fun getLength(): Int {
            return self.ownedNFTs.keys.length
        }

        access(all) view fun borrowNFT(_ id: UInt64): &{NonFungibleToken.NFT}? {
            return &self.ownedNFTs[id]
        }

        /// Borrow the view resolver for the specified NFT ID
        access(all) view fun borrowViewResolver(id: UInt64): &{ViewResolver.Resolver}? {
            if let nft = &self.ownedNFTs[id] as &ExampleCrossVMNFT.NFT? {
                return nft as &{ViewResolver.Resolver}
            }
            return nil
        }

        /// createEmptyCollection creates an empty Collection of the same type
        /// and returns it to the caller
        /// @return A an empty collection of the same type
        access(all) fun createEmptyCollection(): @{NonFungibleToken.Collection} {
            return <-ExampleCrossVMNFT.createEmptyCollection(nftType: Type<@ExampleCrossVMNFT.NFT>())
        }

        access(CrossVMNFT.Bridgeable) fun bridgeToEVM(id: UInt64, to: EVM.EVMAddress, tollFee: @{FungibleToken.Vault}) {
            return ExampleCrossVMNFT.bridgeNFTToEVM(token: <-self.withdraw(withdrawID: id), to: to, tollFee: <-tollFee)
        }
    }

    /// createEmptyCollection creates an empty Collection for the specified NFT type
    /// and returns it to the caller so that they can own NFTs
    access(all) fun createEmptyCollection(nftType: Type): @{NonFungibleToken.Collection} {
        return <- create Collection()
    }

    /// Function that returns all the Metadata Views implemented by a Non Fungible Token
    ///
    /// @return An array of Types defining the implemented views. This value will be used by
    ///         developers to know which parameter to pass to the resolveView() method.
    ///
    access(all) view fun getContractViews(resourceType: Type?): [Type] {
        return [
            Type<MetadataViews.NFTCollectionData>(),
            Type<MetadataViews.NFTCollectionDisplay>()
        ]
    }

    /// Function that resolves a metadata view for this contract.
    ///
    /// @param view: The Type of the desired view.
    /// @return A structure representing the requested view.
    ///
    access(all) fun resolveContractView(resourceType: Type?, viewType: Type): AnyStruct? {
        switch viewType {
            case Type<MetadataViews.NFTCollectionData>():
                let collectionData = MetadataViews.NFTCollectionData(
                    storagePath: /storage/exampleCrossVMNFTCollection,
                    publicPath: /public/exampleCrossVMNFTCollection,
                    publicCollection: Type<&ExampleCrossVMNFT.Collection>(),
                    publicLinkedType: Type<&ExampleCrossVMNFT.Collection>(),
                    createEmptyCollectionFunction: (fun(): @{NonFungibleToken.Collection} {
                        return <-ExampleCrossVMNFT.createEmptyCollection(nftType: Type<@ExampleCrossVMNFT.NFT>())
                    })
                )
                return collectionData
            case Type<MetadataViews.NFTCollectionDisplay>():
                let media = MetadataViews.Media(
                    file: MetadataViews.HTTPFile(
                        url: "https://assets.website-files.com/5f6294c0c7a8cdd643b1c820/5f6294c0c7a8cda55cb1c936_Flow_Wordmark.svg"
                    ),
                    mediaType: "image/svg+xml"
                )
                return MetadataViews.NFTCollectionDisplay(
                    name: "The Example Collection",
                    description: "This collection is used as an example to help you develop your next Flow NFT.",
                    externalURL: MetadataViews.ExternalURL("https://example-nft.onflow.org"),
                    squareImage: media,
                    bannerImage: media,
                    socials: {
                        "twitter": MetadataViews.ExternalURL("https://twitter.com/flow_blockchain")
                    }
                )
        }
        return nil
    }

    access(all) view fun getLockedNFTCount(): Int {
        return self.locker.getLength()
    }
    access(all) view fun borrowLockedNFT(id: UInt64): &{NonFungibleToken.NFT}? {
        return self.locker.borrowNFT(id)
    }
    access(all) view fun isLocked(id: UInt64): Bool {
        return self.locker.borrowNFT(id) != nil
    }

    /// Retrieves the corresponding EVM contract address, assuming a 1:1 relationship between VM implementations
    // TODO: Make view once EVMAddress.address() is view
    access(all) fun getEVMContractAddress(): EVM.EVMAddress {
        return self.evmNFTContractAddress
    }

    /// Returns the amount of fungible tokens required to bridge an NFT
    ///
    access(all) view fun getFeeAmount(): UFix64 {
        // TODO: Update value
        return self.bridgingFee
    }
    /// Returns the type of fungible tokens the bridge accepts for fees
    ///
    access(all) view fun getFeeVaultType(): Type {
        return Type<@FlowToken.Vault>()
    }

    /// Public entrypoint to bridge NFTs from Flow to EVM - cross-account bridging supported (e.g. straight to EOA)
    ///
    /// @param token: The NFT to be bridged
    /// @param to: The NFT recipient in FlowEVM
    /// @param tollFee: The fee paid for bridging
    ///
    access(all) fun bridgeNFTToEVM(token: @{NonFungibleToken.NFT}, to: EVM.EVMAddress, tollFee: @{FungibleToken.Vault}) {
        pre {
            tollFee.getType() == self.getFeeVaultType(): "Invalid token type paid as fee"
            tollFee.balance == self.getFeeAmount(): "Invalid fee amount"
            token.getType() == self.lockedNFTType: "Invalid NFT type" // Add this as field/getter in IFlowEVMNFTBridge?
        }
        self.depositTollFee(<-tollFee)
        let id: UInt64 = token.id
        let evmID: UInt256 = CrossVMNFT.getEVMID(from: &token) ?? panic("Could not get EVM ID from bridging NFT")

        var uri: String = ""
        self.locker.deposit(token: <-token)
        self.borrowCOA().call(
            to: self.evmNFTContractAddress,
            data: FlowEVMBridgeUtils.encodeABIWithSignature("safeMint(address,uint256,string)", [to, evmID, uri]),
            gasLimit: 15000000,
            value: 0.0
        )
    }

    /// Public entrypoint to bridge NFTs from EVM to Flow
    ///
    /// @param caller: The caller executing the bridge - must be passed to check EVM state pre- & post-call in scope
    /// @param calldata: Caller-provided approve() call, enabling contract COA to operate on NFT in EVM contract
    /// @param id: The NFT ID to bridged
    /// @param evmContractAddress: Address of the EVM address defining the NFT being bridged - also call target
    /// @param tollFee: The fee paid for bridging
    ///
    /// @returns The bridged NFT
    ///
    access(all) fun bridgeNFTFromEVM(
        caller: &EVM.BridgedAccount,
        calldata: [UInt8],
        id: UInt256,
        evmContractAddress: EVM.EVMAddress,
        tollFee: @{FungibleToken.Vault}
    ): @{NonFungibleToken.NFT} {
        
    }

    access(self) fun borrowCOA(): &EVM.BridgedAccount {
        return self.account.storage.borrow<&EVM.BridgedAccount>(from: /storage/evm)
            ?? panic("Could not borrow the bridged account")
    }

    /// Deposits fees to the contract account's FlowToken Vault - helps fund asset storage
    access(self) fun depositTollFee(_ tollFee: @{FungibleToken.Vault}) {
        pre {
            tollFee.getType() == self.getFeeVaultType(): "Fee paid in invalid token type"
        }
        let vault = self.account.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Could not borrow FlowToken.Vault reference")
        vault.deposit(from: <-tollFee)
    }

    /// Resource that an admin or something similar would own to be
    /// able to mint new NFTs
    ///
    access(all) resource NFTMinter {

        /// mintNFT mints a new NFT with a new ID
        /// and returns it to the calling context
        access(all) fun mintNFT(
            name: String,
            description: String,
            thumbnail: String,
            royalties: [MetadataViews.Royalty]
        ): @ExampleCrossVMNFT.NFT {

            let metadata: {String: AnyStruct} = {}
            let currentBlock = getCurrentBlock()
            metadata["mintedBlock"] = currentBlock.height
            metadata["mintedTime"] = currentBlock.timestamp

            // this piece of metadata will be used to show embedding rarity into a trait
            metadata["foo"] = "bar"

            // create a new NFT
            var newNFT <- create NFT(
                name: name,
                description: description,
                thumbnail: thumbnail,
                royalties: royalties,
                metadata: metadata,
            )

            return <-newNFT
        }
    }

    init() {

        // Set the named paths
        self.MinterStoragePath = /storage/exampleCrossVMNFTMinter

        // Create a Collection resource and save it to storage
        let collection <- create Collection()
        let defaultStoragePath = collection.storagePath
        let defaultPublicPath = collection.publicPath
        self.account.storage.save(<-collection, to: defaultStoragePath)

        // create a public capability for the collection
        let collectionCap = self.account.capabilities.storage.issue<&ExampleCrossVMNFT.Collection>(defaultStoragePath)
        self.account.capabilities.publish(collectionCap, at: defaultPublicPath)

        // Create a Minter resource and save it to storage
        let minter <- create NFTMinter()
        self.account.storage.save(<-minter, to: self.MinterStoragePath)

        self.lockedNFTType = Type<@ExampleCrossVMNFT.NFT>()
        if self.account.storage.type(at: /storage/evm) == nil {
            self.account.storage.save(<-EVM.createBridgedAccount(), to: /storage/evm)
        }
        let coa = self.account.storage.borrow<&EVM.BridgedAccount>(from: /storage/evm)
            ?? panic("Could not borrow the bridged account")
        // TODO: add compiled bytecode of .sol contract implementation
        let bytecode = ""
        self.evmNFTContractAddress = coa.deploy(
            code: bytecode.decodeHex(),
            gasLimit: 12000000,
            value: EVM.Balance(flow: 0.0)
        )
        self.flowNFTContractAddress = self.account.address
        self.bridgingFee = 0.0
        self.locker <- self.createEmptyCollection(nftType: self.lockedNFTType)
    }
}
 
