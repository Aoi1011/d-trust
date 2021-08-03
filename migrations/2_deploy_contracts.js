const DTRUSTFactory = artifacts.require("DTRUSTFactory");
const DTRUST = artifacts.require("DTRUST");
const ControKey = artifacts.require("ControlKey");

module.exports = async function (deployer, network, accounts) {

    deployer.deploy(DTRUST, "DTRUSTAdmin", "DTA", "DTRUSTAdmin", accounts[0], accounts[0], accounts[0], accounts[0]).then(() => {
        console.log(DTRUST.address);
    });

    deployer.deploy(DTRUSTFactory).then(() => {
        console.log(DTRUSTFactory.address);
    });

    deployer.deploy(ControKey).then(() => {
        console.log(ControKey.address);
    })

};