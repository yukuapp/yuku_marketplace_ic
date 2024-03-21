# YUKU MARKETPLACE
This repository contains the source code for the Yuku NFT Marketplace

See the [official website](https://yuku.app/marketplace) for more informations about the project.

## Project Structure

- [`src/yuku.mo`](src/yuku.mo): yuku NFT marketplace explore source code
- [`src/launchpad.mo`](src/launchpad.mo): Yuku NFT Marketplace launchpad source code 
- [`src/ERC72.mo`](src/ERC721.mo): Yuku NFT Marketplace NFT standard
- [`script/deploy`](scripts/deploy): The setup scripts
- [`sns`](sns): Sns init yml

## Development instructions
1. Clone this repository:
  ```sh
  git clone git@github.com:yukuapp/yuku_marketplace_ic.git
  ```

2. Make sure you have installed the following software.

   [`dfx`](https://internetcomputer.org/docs/current/references/samples/svelte/sveltekit-starter/#dfx)

   [`vessel`](https://github.com/dfinity/vessel)
   
   [`jq`](https://pypi.org/project/jq/)

3. Run the locally setup script.
    ```sh
    ./scripts/local_deploy.sh
    ```